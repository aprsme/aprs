defmodule Mix.Tasks.Aprs.ParseFileTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Aprs.ParseFile

  setup do
    dir = Path.join(System.tmp_dir!(), "aprs_parse_file_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    Mix.shell(Mix.Shell.Process)

    %{input: Path.join(dir, "packets.txt"), output: Path.join(dir, "failures.jsonl")}
  end

  test "logs failing lines and skips comments and blanks", %{input: input, output: output} do
    File.write!(input, """
    # aprsc 2.1.19 test server

    N0CALL-9>APRS,TCPIP*:!4903.50N/07201.75W>Test
    totally bogus line
    N0CALL>APRS:@nonsense
    """)

    ParseFile.run([input, "--output", output])

    assert [hard, payload] = output |> File.read!() |> String.split("\n", trim: true)

    assert hard =~ ~s("seq":1)
    assert hard =~ ~s("raw":"totally bogus line")
    assert hard =~ ~s("error":"invalid_packet")

    assert payload =~ ~s("seq":2)
    assert payload =~ ~s("error":"payload: Invalid timestamped position format")
  end

  test "--hard-errors-only skips payload failures", %{input: input, output: output} do
    File.write!(input, "N0CALL>APRS:@nonsense\ntotally bogus line\n")

    ParseFile.run([input, "--output", output, "--hard-errors-only"])

    assert [failure] = output |> File.read!() |> String.split("\n", trim: true)
    assert failure =~ ~s("raw":"totally bogus line")
  end

  test "handles lines that are not valid utf8", %{input: input, output: output} do
    File.write!(input, <<"totally bogus ", 0xFF, "\n">>)

    ParseFile.run([input, "--output", output])

    assert [failure] = output |> File.read!() |> String.split("\n", trim: true)
    assert failure =~ ~s("raw":"totally bogus \\\\xFF")
  end

  test "exits when the input file is missing", %{input: input, output: output} do
    assert catch_exit(ParseFile.run([input, "--output", output])) == {:shutdown, 1}
  end

  test "exits when no input file is given", %{output: output} do
    assert catch_exit(ParseFile.run(["--output", output])) == {:shutdown, 1}
    assert_receive {:mix_shell, :error, ["Error: input file not found: (none given)"]}
  end
end
