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

  defp read_failures(output) do
    output |> File.read!() |> String.split("\n", trim: true)
  end

  # Minimal APRS-IS stand-in: accepts one client, captures its login line,
  # writes the given frames, then either idles or closes.
  defp start_fake_aprs_is(frames, opts) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, packet: :line, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    login_task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        {:ok, login} = :gen_tcp.recv(socket, 0, 5_000)
        :inet.setopts(socket, packet: :raw)
        Enum.each(frames, &:gen_tcp.send(socket, &1))

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
end
