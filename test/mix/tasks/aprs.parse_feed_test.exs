defmodule Mix.Tasks.Aprs.ParseFeedTest do
  # Safe to run concurrently: `Mix.Shell.Process` sends shell output to the
  # process that produced it, the run happens in the test process, the session
  # transport is read from that process's own dictionary, and every socket and
  # output path is per-test.
  use ExUnit.Case, async: true

  alias Mix.Tasks.Aprs.ParseFeed

  @good "N0CALL-9>APRS,TCPIP*:!4903.50N/07201.75W>Test"
  @bad_no_path "totally bogus line"
  @bad_payload "N0CALL>APRS:@nonsense"

  # A transport whose whole session is a script held in the test process, so
  # chunk boundaries, timeouts and socket errors land exactly where the test
  # puts them instead of being coaxed out of a real socket. It also covers what
  # no timing on a real socket can arrange: a send that fails on a connection
  # that has only just come up, and a receive that fails with neither a timeout
  # nor a close. A script that runs out is a server that hung up.
  defmodule ScriptedTransport do
    @moduledoc false

    def connect(_address, _port, _options, _timeout), do: {:ok, :scripted_socket}

    def send(_socket, login) do
      Process.put(:login, login)
      Process.get(:send_result, :ok)
    end

    def close(_socket) do
      Process.put(:closed?, true)
      :ok
    end

    def recv(_socket, _length, timeout) do
      Process.put(:recv_timeouts, [timeout | Process.get(:recv_timeouts, [])])

      case Process.get(:recvs, []) do
        [result | rest] ->
          Process.put(:recvs, rest)
          result

        [] ->
          {:error, :closed}
      end
    end
  end

  setup do
    output = Path.join(System.tmp_dir!(), "aprs_parse_feed_#{System.unique_integer([:positive])}/failures.jsonl")
    on_exit(fn -> File.rm_rf(Path.dirname(output)) end)

    Mix.shell(Mix.Shell.Process)

    %{output: output}
  end

  test "logs failing packets and why, ignoring good ones", %{output: output} do
    frames = [
      "# aprsc 2.1.19 test server\r\n",
      @good <> "\r\n",
      @bad_no_path <> "\r\n",
      @bad_payload <> "\r\n"
    ]

    {port, login_task} = start_fake_aprs_is(frames, close_after_send: true)

    run_socket(port, output, ["--duration", "10", "--progress", "0", "--callsign", "TESTCALL", "--filter", "r/1/2/3"])

    login = Task.await(login_task, 5_000)
    assert login =~ "user TESTCALL pass -1 vers aprs-parse-feed #{Aprs.version()}"
    assert login =~ "filter r/1/2/3"

    assert [hard, payload] = read_failures(output)

    assert hard =~ ~s("seq":1)
    assert hard =~ ~s("raw":"#{@bad_no_path}")
    assert hard =~ ~s("error":"invalid_packet")

    assert payload =~ ~s("seq":2)
    assert payload =~ ~s("raw":"#{@bad_payload}")
    assert payload =~ ~s("error":"payload: Invalid timestamped position format")
  end

  test "--hard-errors-only skips payload failures", %{output: output} do
    {port, _login} = start_fake_aprs_is([@bad_payload <> "\r\n", @bad_no_path <> "\r\n"], close_after_send: true)

    run_socket(port, output, ["--duration", "10", "--progress", "0", "--hard-errors-only"])

    assert [failure] = read_failures(output)
    assert failure =~ ~s("raw":"#{@bad_no_path}")
  end

  test "reassembles packets split across TCP chunks", %{output: output} do
    script(
      recvs: [
        {:ok, String.slice(@bad_no_path, 0..5)},
        {:ok, String.slice(@bad_no_path, 6..-1//1) <> "\r\n"},
        {:ok, @good <> "\r\n"}
      ]
    )

    run_scripted(output, ["--duration", "10", "--progress", "0"])

    assert [failure] = read_failures(output)
    assert failure =~ ~s("raw":"#{@bad_no_path}")
  end

  test "writes an empty file when nothing fails", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n"], close_after_send: true)

    run_socket(port, output, ["--duration", "10", "--progress", "0"])

    assert File.read!(output) == ""
  end

  test "exits when no address answers", %{output: output} do
    assert catch_exit(run_socket(65_000, output, ["--duration", "10", "--progress", "0"])) == {:shutdown, 1}
  end

  test "an address whose login cannot be sent is closed and abandoned", %{output: output} do
    script(send_result: {:error, :closed})

    assert catch_exit(run_scripted(output, ["--duration", "1", "--progress", "0"])) == {:shutdown, 1}

    assert Process.get(:closed?), "the socket of an address that cannot be used must be closed"
    assert_receive {:mix_shell, :info, ["  127.0.0.1 unavailable (:closed), trying next address"]}
    assert_receive {:mix_shell, :error, [message]}
    assert message =~ "all_addresses_failed"
  end

  test "stops on a stop signal, with no duration limit", %{output: output} do
    {port, _login} = start_fake_aprs_is([], close_after_send: false)

    send(self(), :parse_feed_stop)
    run_socket(port, output, ["--duration", "0", "--progress", "0"])

    assert_shell_info("Stopped: stop signal received")
  end

  test "with no duration limit the run lasts until the server hangs up", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n"], close_after_send: true)

    run_socket(port, output, ["--duration", "0", "--progress", "0"])

    assert_shell_info("Stopped: connection closed by server")
  end

  test "stops when the duration elapses", %{output: output} do
    {port, _login} = start_fake_aprs_is([], close_after_send: false)

    run_socket(port, output, ["--duration", "0.05", "--progress", "0"])

    assert_shell_info("Stopped: duration elapsed")
  end

  test "describes a whole-number duration without a decimal point", %{output: output} do
    script(recvs: [])

    run_scripted(output, ["--duration", "10", "--progress", "0"])

    assert_shell_info("will stop after 10s (or a stop signal)")
  end

  test "an idle receive does not end the run", %{output: output} do
    script(recvs: [{:error, :timeout}, {:error, :timeout}, {:ok, @bad_no_path <> "\r\n"}])

    run_scripted(output, ["--duration", "0", "--progress", "0"])

    # The frame was still read after two idle receives, so neither ended the run.
    assert [failure] = read_failures(output)
    assert failure =~ ~s("raw":"#{@bad_no_path}")
    assert_shell_info("Stopped: connection closed by server")
  end

  test "an idle receive is never allowed to wait past the deadline", %{output: output} do
    script(recvs: [{:error, :timeout}])

    run_scripted(output, ["--duration", "0.02", "--progress", "0"])

    timeouts = Process.get(:recv_timeouts, [])
    assert Enum.all?(timeouts, &(&1 <= 20)), "an idle receive waited past the deadline: #{inspect(timeouts)}"
  end

  test "stops when the packet limit is reached", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n", @good <> "\r\n"], close_after_send: false)

    run_socket(port, output, ["--duration", "10", "--progress", "0", "--limit", "1"])

    assert_shell_info("Stopped: packet limit reached")
    assert File.read!(output) == ""
  end

  test "stops when the failure limit is reached", %{output: output} do
    frames = [@bad_no_path <> "\r\n", @bad_no_path <> "\r\n"]
    {port, _login} = start_fake_aprs_is(frames, close_after_send: false)

    run_socket(port, output, ["--duration", "10", "--progress", "0", "--max-failures", "1"])

    assert_shell_info("Stopped: failure limit reached")
  end

  test "reports a socket error that is neither a timeout nor a close", %{output: output} do
    script(recvs: [{:error, :einval}])

    run_scripted(output, ["--duration", "10", "--progress", "0"])

    assert_shell_info("Stopped: socket error: :einval")
  end

  test "logs an unterminated frame past the frame limit and resyncs", %{output: output} do
    overlong = String.duplicate("x", 1100)
    script(recvs: [{:ok, overlong}, {:ok, "\r\n" <> @bad_no_path <> "\r\n"}])

    run_scripted(output, ["--duration", "10", "--progress", "0"])

    assert [overlong_failure, resynced] = read_failures(output)
    assert overlong_failure =~ ~s("error":"frame_exceeds_max_length")
    assert resynced =~ ~s("raw":"#{@bad_no_path}")
  end

  test "ignores blank lines and stops echoing server comments after the first two", %{output: output} do
    frames = [
      "# first\r\n",
      "\r\n",
      "# second\r\n",
      "# third\r\n",
      @good <> "\r\n"
    ]

    {port, _login} = start_fake_aprs_is(frames, close_after_send: true)

    run_socket(port, output, ["--duration", "10", "--progress", "0"])

    assert_receive {:mix_shell, :info, ["APRS-IS: # first"]}
    assert_receive {:mix_shell, :info, ["APRS-IS: # second"]}
    refute_received {:mix_shell, :info, ["APRS-IS: # third"]}
    assert File.read!(output) == ""
  end

  test "reports progress every N packets", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n", @good <> "\r\n"], close_after_send: true)

    run_socket(port, output, ["--duration", "10", "--progress", "1"])

    assert_receive {:mix_shell, :info, ["  2 packets, 0 failures"]}
  end

  test "stays quiet until the progress interval is reached", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n", @good <> "\r\n"], close_after_send: true)

    run_socket(port, output, ["--duration", "10", "--progress", "5"])

    refute_received {:mix_shell, :info, ["  2 packets, 0 failures"]}
  end

  test "exits when the server name does not resolve", %{output: output} do
    assert catch_exit(
             ParseFeed.run([
               "--server",
               "aprs-parse-feed-test.invalid",
               "--duration",
               "1",
               "--progress",
               "0",
               "--output",
               output
             ])
           ) == {:shutdown, 1}

    assert_receive {:mix_shell, :error, [message]}
    assert message =~ "dns_failed"
  end

  defp run_socket(port, output, args) do
    ParseFeed.run(["--server", "127.0.0.1", "--port", Integer.to_string(port), "--output", output] ++ args)
  end

  defp run_scripted(output, args) do
    ParseFeed.run(["--server", "127.0.0.1", "--output", output] ++ args)
  end

  # The transport and its script live in this process, so a concurrent test
  # cannot see either, and each test starts with an empty dictionary.
  defp script(opts) do
    Process.put(:aprs_feed_transport, ScriptedTransport)
    Enum.each(opts, fn {key, value} -> Process.put(key, value) end)
  end

  # The run happens in this process, so every shell message it produced is
  # already in the mailbox by the time it returns: nothing here waits.
  defp assert_shell_info(fragment) do
    assert shell_info(fragment) =~ fragment
  end

  defp shell_info(fragment) do
    receive do
      {:mix_shell, :info, [message]} ->
        if String.contains?(message, fragment), do: message, else: shell_info(fragment)
    after
      0 -> flunk("no shell output containing #{inspect(fragment)}")
    end
  end

  defp read_failures(output) do
    output |> File.read!() |> String.split("\n", trim: true)
  end

  # Minimal APRS-IS stand-in: accepts one client, captures its login line,
  # writes the given frames, then either hangs up or holds the connection open
  # so the run stops on one of its own limits.
  defp start_fake_aprs_is(frames, opts) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, packet: :line, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    login_task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        login = login_line(socket)
        :inet.setopts(socket, packet: :raw)
        Enum.each(frames, &:gen_tcp.send(socket, &1))

        if Keyword.fetch!(opts, :close_after_send) do
          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
        else
          Process.sleep(:infinity)
        end

        login
      end)

    # A hold is only ever ended by this: exiting normally would leave a linked
    # task holding a listening socket, because a normal exit signal is ignored.
    on_exit(fn -> Process.exit(login_task.pid, :kill) end)

    {port, login_task}
  end

  # A client that hangs up before sending a login is something a test sets up on
  # purpose. Reporting it belongs to that test, not to a crash in this task that
  # would land on whichever test happened to still be running.
  defp login_line(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, login} -> login
      {:error, reason} -> {:error, reason}
    end
  end
end
