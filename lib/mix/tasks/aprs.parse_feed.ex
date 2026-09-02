defmodule Mix.Tasks.Aprs.ParseFeed do
  @shortdoc "Stream the APRS-IS global feed and log packets that fail to parse"

  @moduledoc """
  Connects to an APRS-IS server, parses every packet off the live feed, ignores
  everything that parses cleanly, and appends every failure to a gitignored
  output file: one JSON object per line with the packet and why it failed.

      {"seq":1,"received_at":"2026-09-02T15:24:11.482Z","error":"payload: Invalid position format","raw":"N0CALL>APRS:!invalidposition"}

  JSON Lines is readable as-is and trivially machine-parseable (`jq`). Lines are
  flushed as failures happen, so an interrupted run still leaves usable output.

  Login is receive-only (passcode `-1` by default), so no amateur license is
  required. The default port carries the unfiltered global feed.

  ## What counts as a failure

  Both kinds of parse failure are logged:

    * hard - `Aprs.parse/1` returned `{:error, reason}`. Rare on a live feed,
      because APRS-IS servers validate framing before relaying.
    * payload - `Aprs.parse/1` returned `{:ok, packet}` but the payload parser
      gave up, leaving an error in `data_extended` (e.g. `"Invalid position
      format"`) or no `data_extended` at all (e.g. `:unknown_datatype`). This is
      where essentially all real-world parser gaps show up.

  Pass `--hard-errors-only` to log just the `{:error, _}` returns.

  ## Usage

      mix aprs.parse_feed
      mix aprs.parse_feed --duration 600
      mix aprs.parse_feed --duration 0            # until stopped
      mix aprs.parse_feed --limit 50000 --output tmp/failures.jsonl
      mix aprs.parse_feed --port 14580 --filter "r/33/-96/500"

  ## Options

    * `--server` / `-s` - APRS-IS host (default: `noam.aprs2.net`)
    * `--port` / `-p` - APRS-IS port (default: `10152`, the unfiltered feed)
    * `--filter` / `-f` - server-side filter; requires a filter port such as 14580
    * `--duration` / `-d` - seconds to run, `0` for unlimited (default: `60`)
    * `--limit` / `-n` - stop after this many packets (default: unlimited)
    * `--max-failures` - stop after this many failures (default: unlimited)
    * `--callsign` - login callsign (default: `$APRS_CALLSIGN`, else `N0CALL`)
    * `--passcode` - login passcode (default: `-1`, receive-only)
    * `--progress` - packets between progress lines, `0` to silence (default: `2000`)
    * `--hard-errors-only` - log only `{:error, _}` returns, not payload failures
    * `--output` / `-o` - output file (default: `tmp/aprs_parse_failures.jsonl`)

  ## Stopping a run

  `SIGTERM` and `SIGQUIT` stop the run cleanly, so an unbounded run can be ended
  with `kill -TERM <beam pid>`. `SIGINT` (Ctrl-C) cannot be trapped by the
  runtime and aborts the VM, which is also fine: output is already on disk.
  """

  use Mix.Task

  alias Aprs.FeedAudit.Failure
  alias Aprs.FeedAudit.Verdict

  @default_server "noam.aprs2.net"
  @default_port 10_152
  @default_output "tmp/aprs_parse_failures.jsonl"
  @default_duration 60
  @default_progress 2_000

  # A frame with no newline within this many bytes is malformed framing rather
  # than a packet (APRS-IS frames are at most 512 bytes); log it and resync.
  @max_frame_bytes 1_024
  @recv_timeout 1_000
  # Per-address connect budget; the pool is walked, so keep it short.
  @connect_timeout 8_000
  # SIGINT cannot be trapped by the runtime, so a clean stop is driven by the
  # signals that can: SIGTERM and SIGQUIT.
  @stop_signals [:sigterm, :sigquit]

  @impl Mix.Task
  def run(argv) do
    {opts, _positional, _invalid} =
      OptionParser.parse(argv,
        aliases: [s: :server, p: :port, f: :filter, d: :duration, n: :limit, o: :output],
        strict: [
          server: :string,
          port: :integer,
          filter: :string,
          duration: :integer,
          limit: :integer,
          max_failures: :integer,
          callsign: :string,
          passcode: :string,
          progress: :integer,
          hard_errors_only: :boolean,
          output: :string
        ]
      )

    _ = Mix.Task.run("compile")

    config = build_config(opts)
    io = open_output(config.output)

    case connect(config) do
      {:ok, socket} ->
        counts = stream(socket, config, io)
        :ok = :gen_tcp.close(socket)
        :ok = File.close(io)
        print_summary(counts, config)

      {:error, reason} ->
        :ok = File.close(io)
        Mix.shell().error("Could not connect to #{config.server}:#{config.port}: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp build_config(opts) do
    duration = Keyword.get(opts, :duration, @default_duration)

    %{
      server: Keyword.get(opts, :server, @default_server),
      port: Keyword.get(opts, :port, @default_port),
      filter: Keyword.get(opts, :filter),
      login: Keyword.get(opts, :callsign) || System.get_env("APRS_CALLSIGN") || "N0CALL",
      passcode: Keyword.get(opts, :passcode, "-1"),
      duration: duration,
      deadline: deadline(duration),
      limit: Keyword.get(opts, :limit),
      max_failures: Keyword.get(opts, :max_failures),
      progress: Keyword.get(opts, :progress, @default_progress),
      mode: if(Keyword.get(opts, :hard_errors_only, false), do: :hard, else: :all),
      output: Keyword.get(opts, :output, @default_output)
    }
  end

  defp deadline(duration) when is_integer(duration) and duration > 0 do
    System.monotonic_time(:millisecond) + duration * 1_000
  end

  defp deadline(_duration), do: nil

  defp open_output(path) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.open!(path, [:write, :binary])
  end

  # aprs2.net names are round-robin pools that routinely contain unreachable
  # members, and `:gen_tcp.connect/4` with a hostname only tries one address.
  # Resolve up front and walk the list until a server answers.
  defp connect(config) do
    Mix.shell().info("Connecting to #{config.server}:#{config.port} as #{config.login} (receive-only)...")

    with {:ok, addresses} <- resolve(config.server) do
      connect_any(addresses, config, [])
    end
  end

  defp resolve(server) do
    case :inet.getaddrs(String.to_charlist(server), :inet) do
      {:ok, addresses} -> {:ok, Enum.shuffle(addresses)}
      {:error, reason} -> {:error, {:dns_failed, reason}}
    end
  end

  defp connect_any([], _config, errors) do
    {:error, {:all_addresses_failed, Enum.reverse(errors)}}
  end

  defp connect_any([address | rest], config, errors) do
    case open_session(address, config) do
      {:ok, socket} ->
        Mix.shell().info("Connected to #{format_address(address)}:#{config.port}")
        {:ok, socket}

      {:error, reason} ->
        Mix.shell().info("  #{format_address(address)} unavailable (#{inspect(reason)}), trying next address")
        connect_any(rest, config, [{format_address(address), reason} | errors])
    end
  end

  defp open_session(address, config) do
    case :gen_tcp.connect(address, config.port, [:binary, active: false, packet: :raw], @connect_timeout) do
      {:ok, socket} -> send_login(socket, config)
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_login(socket, config) do
    case :gen_tcp.send(socket, login_string(config)) do
      :ok ->
        {:ok, socket}

      {:error, reason} ->
        :gen_tcp.close(socket)
        {:error, reason}
    end
  end

  defp format_address(address), do: address |> :inet.ntoa() |> List.to_string()

  defp login_string(config) do
    filter = if config.filter, do: " filter #{config.filter}", else: ""
    "user #{config.login} pass #{config.passcode} vers aprs-parse-feed #{Aprs.version()}#{filter}\r\n"
  end

  defp stream(socket, config, io) do
    signal_ids = trap_stop_signals()
    describe_run(config)

    state = %{
      io: io,
      config: config,
      buffer: "",
      received: 0,
      failed: 0,
      server_messages: 0,
      next_progress: config.progress
    }

    {state, stop_reason} = loop(socket, state)
    untrap_stop_signals(signal_ids)

    Map.put(state, :stop_reason, stop_reason)
  end

  defp describe_run(config) do
    limits =
      [
        if(config.duration > 0, do: "#{config.duration}s"),
        if(config.limit, do: "#{config.limit} packets"),
        if(config.max_failures, do: "#{config.max_failures} failures")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" or ")

    stop_when = if limits == "", do: "a stop signal", else: "#{limits} (or a stop signal)"
    Mix.shell().info("Parsing feed; will stop after #{stop_when}. Failures: #{config.output}")
  end

  defp loop(socket, state) do
    case stop_reason(state) do
      nil -> receive_chunk(socket, state)
      reason -> {state, reason}
    end
  end

  defp receive_chunk(socket, state) do
    case :gen_tcp.recv(socket, 0, @recv_timeout) do
      {:ok, chunk} -> loop(socket, handle_chunk(chunk, state))
      {:error, :timeout} -> loop(socket, state)
      {:error, :closed} -> {state, :connection_closed}
      {:error, reason} -> {state, {:socket_error, reason}}
    end
  end

  defp stop_reason(state) do
    cond do
      stop_signalled?() -> :signal_stop
      deadline_passed?(state.config.deadline) -> :duration_reached
      limit_reached?(state.config.limit, state.received) -> :packet_limit_reached
      limit_reached?(state.config.max_failures, state.failed) -> :failure_limit_reached
      true -> nil
    end
  end

  defp stop_signalled? do
    receive do
      :parse_feed_stop -> true
    after
      0 -> false
    end
  end

  defp deadline_passed?(nil), do: false
  defp deadline_passed?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  defp limit_reached?(nil, _count), do: false
  defp limit_reached?(limit, count), do: count >= limit

  defp handle_chunk(chunk, state) do
    {lines, buffer} = split_lines(state.buffer <> chunk)

    lines
    |> Enum.reduce(%{state | buffer: buffer}, &handle_line/2)
    |> flush_overlong_buffer()
    |> report_progress()
  end

  defp split_lines(buffer) do
    {lines, [rest]} = buffer |> :binary.split("\n", [:global]) |> Enum.split(-1)
    {lines, rest}
  end

  # An unterminated frame past the APRS-IS frame limit is itself a malformed
  # packet: log it, then resync on the next newline.
  defp flush_overlong_buffer(%{buffer: buffer} = state) when byte_size(buffer) > @max_frame_bytes do
    %{write_failure(state, buffer, :frame_exceeds_max_length) | buffer: ""}
  end

  defp flush_overlong_buffer(state), do: state

  defp handle_line(line, state) do
    line |> strip_suffix("\n") |> strip_suffix("\r") |> classify_line(state)
  end

  defp classify_line("", state), do: state

  defp classify_line("#" <> _comment = line, state) do
    if state.server_messages < 2, do: Mix.shell().info("APRS-IS: #{line}")
    %{state | server_messages: state.server_messages + 1}
  end

  defp classify_line(line, state) do
    case Verdict.classify(Aprs.parse(line), state.config.mode) do
      :ok -> %{state | received: state.received + 1}
      {:failure, reason} -> write_failure(state, line, reason)
    end
  end

  defp write_failure(state, raw, reason) do
    failure = Failure.build(raw, reason, seq: state.failed + 1)
    IO.binwrite(state.io, [Failure.to_json(failure), "\n"])

    %{state | received: state.received + 1, failed: state.failed + 1}
  end

  defp report_progress(%{next_progress: next} = state) when next <= 0, do: state

  defp report_progress(%{next_progress: next} = state) do
    if state.received >= next do
      Mix.shell().info("  #{state.received} packets, #{state.failed} failures")
      %{state | next_progress: next + state.config.progress}
    else
      state
    end
  end

  defp print_summary(counts, config) do
    Mix.shell().info("""

    Stopped: #{stop_label(counts.stop_reason)}
    Received #{counts.received} packets: #{counts.received - counts.failed} parsed, #{counts.failed} failed
    Failures: #{config.output}\
    """)
  end

  defp stop_label(:duration_reached), do: "duration elapsed"
  defp stop_label(:packet_limit_reached), do: "packet limit reached"
  defp stop_label(:failure_limit_reached), do: "failure limit reached"
  defp stop_label(:signal_stop), do: "stop signal received"
  defp stop_label(:connection_closed), do: "connection closed by server"
  defp stop_label({:socket_error, reason}), do: "socket error: #{inspect(reason)}"

  defp strip_suffix(binary, suffix) do
    size = byte_size(binary) - byte_size(suffix)

    if size >= 0 and binary_part(binary, size, byte_size(suffix)) == suffix do
      binary_part(binary, 0, size)
    else
      binary
    end
  end

  defp trap_stop_signals do
    pid = self()
    handler = fn -> notify_stop(pid) end

    Enum.flat_map(@stop_signals, &trap_stop_signal(&1, handler))
  end

  defp trap_stop_signal(signal, handler) do
    case System.trap_signal(signal, handler) do
      {:ok, id} -> [{signal, id}]
      {:error, _reason} -> []
    end
  end

  defp notify_stop(pid) do
    send(pid, :parse_feed_stop)
    :ok
  end

  defp untrap_stop_signals(signal_ids) do
    Enum.each(signal_ids, fn {signal, id} -> System.untrap_signal(signal, id) end)
  end
end
