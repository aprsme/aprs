defmodule Mix.Tasks.Aprs.ParseFeedTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Aprs.ParseFeed

  @good "N0CALL-9>APRS,TCPIP*:!4903.50N/07201.75W>Test"
  @bad_no_path "totally bogus line"
  @bad_payload "N0CALL>APRS:@nonsense"

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

    run(port, output, ["--callsign", "TESTCALL", "--filter", "r/1/2/3"])

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

    run(port, output, ["--hard-errors-only"])

    assert [failure] = read_failures(output)
    assert failure =~ ~s("raw":"#{@bad_no_path}")
  end

  test "reassembles packets split across TCP chunks", %{output: output} do
    frames = [
      String.slice(@bad_no_path, 0..5),
      String.slice(@bad_no_path, 6..-1//1) <> "\r\n",
      @good <> "\r\n"
    ]

    {port, _login} = start_fake_aprs_is(frames, close_after_send: true)

    run(port, output, [])

    assert [failure] = read_failures(output)
    assert failure =~ ~s("raw":"#{@bad_no_path}")
  end

  test "writes an empty file when nothing fails", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n"], close_after_send: true)

    run(port, output, [])

    assert File.read!(output) == ""
  end

  test "exits when no address answers", %{output: output} do
    assert catch_exit(run(65_000, output, ["--server", "127.0.0.1"])) == {:shutdown, 1}
  end

  test "stops on a stop signal, with no duration limit", %{output: output} do
    {port, _login} = start_fake_aprs_is([], close_after_send: false)

    send(self(), :parse_feed_stop)
    run_with(port, output, ["--duration", "0", "--progress", "0"])

    assert_summary("Stopped: stop signal received")
  end

  test "with no duration limit the run lasts until the server hangs up", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n"], close_after_send: true)

    run_with(port, output, ["--duration", "0", "--progress", "0"])

    assert_summary("Stopped: connection closed by server")
  end

  test "stops when the duration elapses, waiting through idle receives", %{output: output} do
    {port, _login} = start_fake_aprs_is([], close_after_send: false)

    run_with(port, output, ["--duration", "1", "--progress", "0"])

    assert_summary("Stopped: duration elapsed")
  end

  test "stops when the packet limit is reached", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n", @good <> "\r\n"], close_after_send: false)

    run_with(port, output, ["--duration", "10", "--progress", "0", "--limit", "1"])

    assert_summary("Stopped: packet limit reached")
    assert File.read!(output) == ""
  end

  test "stops when the failure limit is reached", %{output: output} do
    frames = [@bad_no_path <> "\r\n", @bad_no_path <> "\r\n"]
    {port, _login} = start_fake_aprs_is(frames, close_after_send: false)

    run_with(port, output, ["--duration", "10", "--progress", "0", "--max-failures", "1"])

    assert_summary("Stopped: failure limit reached")
  end

  test "reports a socket error that is neither a timeout nor a close", %{output: output} do
    {port, _login} = start_fake_aprs_is([], close_after_send: false)

    break_client_socket(port)
    run_with(port, output, ["--duration", "10", "--progress", "0"])

    assert_summary("Stopped: socket error: :einval")
  end

  test "logs an unterminated frame past the frame limit and resyncs", %{output: output} do
    overlong = String.duplicate("x", 1100)
    frames = [overlong, {:pause, 200}, "\r\n" <> @bad_no_path <> "\r\n"]
    {port, _login} = start_fake_aprs_is(frames, close_after_send: true)

    run_with(port, output, ["--duration", "10", "--progress", "0"])

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

    run_with(port, output, ["--duration", "10", "--progress", "0"])

    assert_receive {:mix_shell, :info, ["APRS-IS: # first"]}
    assert_receive {:mix_shell, :info, ["APRS-IS: # second"]}
    refute_received {:mix_shell, :info, ["APRS-IS: # third"]}
    assert File.read!(output) == ""
  end

  test "reports progress every N packets", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n", @good <> "\r\n"], close_after_send: true)

    run_with(port, output, ["--duration", "10", "--progress", "1"])

    assert_receive {:mix_shell, :info, ["  2 packets, 0 failures"]}
  end

  test "stays quiet until the progress interval is reached", %{output: output} do
    {port, _login} = start_fake_aprs_is([@good <> "\r\n", @good <> "\r\n"], close_after_send: true)

    run_with(port, output, ["--duration", "10", "--progress", "5"])

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

  defp run(port, output, extra) do
    ParseFeed.run(
      [
        "--server",
        "127.0.0.1",
        "--port",
        Integer.to_string(port),
        "--duration",
        "10",
        "--progress",
        "0",
        "--output",
        output
      ] ++ extra
    )
  end

  defp run_with(port, output, args) do
    ParseFeed.run(["--server", "127.0.0.1", "--port", Integer.to_string(port), "--output", output] ++ args)
  end

  defp assert_summary(line) do
    assert summary_line() =~ line
  end

  defp summary_line do
    receive do
      {:mix_shell, :info, [message]} ->
        if String.contains?(message, "Stopped:"), do: message, else: summary_line()
    after
      15_000 -> flunk("no run summary was printed")
    end
  end

  # A receive on a socket that has been switched to active mode fails with
  # :einval, which is how a socket error other than a close is provoked here.
  # The task runs in this process, so its socket is a port this process owns.
  defp break_client_socket(server_port) do
    test_pid = self()

    spawn_link(fn ->
      test_pid |> await_client_socket(server_port, 500) |> :inet.setopts(active: true)
    end)

    :ok
  end

  defp await_client_socket(pid, server_port, attempts) when attempts > 0 do
    case Enum.find(Port.list(), &client_socket?(&1, pid, server_port)) do
      nil ->
        Process.sleep(10)
        await_client_socket(pid, server_port, attempts - 1)

      port ->
        port
    end
  end

  defp client_socket?(port, pid, server_port) do
    Port.info(port, :name) == {:name, ~c"tcp_inet"} and
      Port.info(port, :connected) == {:connected, pid} and
      match?({:ok, {_address, ^server_port}}, :inet.peername(port))
  end

  defp read_failures(output) do
    output |> File.read!() |> String.split("\n", trim: true)
  end

  # Minimal APRS-IS stand-in: accepts one client, captures its login line,
  # writes the given frames, then either idles or closes. A `{:pause, ms}`
  # frame holds the write back so the next frame lands in its own chunk.
  defp start_fake_aprs_is(frames, opts) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, packet: :line, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    login_task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        {:ok, login} = :gen_tcp.recv(socket, 0, 5_000)
        :inet.setopts(socket, packet: :raw)
        Enum.each(frames, &write_frame(socket, &1))

        if !Keyword.get(opts, :close_after_send, false) do
          # Hold the connection open so the task stops on its own limits.
          Process.sleep(2_000)
        end

        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        login
      end)

    {port, login_task}
  end

  defp write_frame(_socket, {:pause, milliseconds}), do: Process.sleep(milliseconds)
  defp write_frame(socket, frame), do: :gen_tcp.send(socket, frame)
end
