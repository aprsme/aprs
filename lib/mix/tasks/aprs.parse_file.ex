defmodule Mix.Tasks.Aprs.ParseFile do
  @shortdoc "Parse APRS packets from a file and log the ones that fail"

  @moduledoc """
  Reads APRS packets from a text file (one frame per line), parses each one,
  ignores everything that parses cleanly, and appends every failure to an output
  file: one JSON object per line with the packet and why it failed.

      {"seq":1,"received_at":"2026-09-02T15:24:11.482Z","error":"payload: Invalid position format","raw":"N0CALL>APRS:!invalidposition"}

  Blank lines and lines starting with `#` (APRS-IS server comments) are skipped.
  Failure classification matches `mix aprs.parse_feed`: see
  `Aprs.FeedAudit.Verdict`.

  ## Usage

      mix aprs.parse_file packets.txt
      mix aprs.parse_file packets.txt --output tmp/failures.jsonl
      mix aprs.parse_file packets.txt --hard-errors-only

  ## Options

    * `--output` / `-o` - output file (default: `tmp/aprs_parse_failures.jsonl`)
    * `--hard-errors-only` - log only `{:error, _}` returns, not payload failures
  """

  use Mix.Task

  alias Aprs.FeedAudit.Failure
  alias Aprs.FeedAudit.Verdict

  @default_output "tmp/aprs_parse_failures.jsonl"

  @impl Mix.Task
  def run(argv) do
    {opts, positional, _invalid} =
      OptionParser.parse(argv,
        aliases: [o: :output],
        strict: [output: :string, hard_errors_only: :boolean]
      )

    input = List.first(positional)
    output = Keyword.get(opts, :output, @default_output)
    mode = if Keyword.get(opts, :hard_errors_only, false), do: :hard, else: :all

    _ = Mix.Task.run("compile")

    if !(input && File.exists?(input)) do
      Mix.shell().error("Error: input file not found: #{input || "(none given)"}")
      exit({:shutdown, 1})
    end

    {total, failed} = parse_file(input, output, mode)

    Mix.shell().info("""
    Read #{total} packets: #{total - failed} parsed, #{failed} failed
    Failures: #{output}\
    """)
  end

  defp parse_file(input, output, mode) do
    output |> Path.dirname() |> File.mkdir_p!()
    io = File.open!(output, [:write, :binary])

    try do
      input
      |> File.stream!()
      |> Stream.map(&strip_eol/1)
      |> Stream.reject(&skip_line?/1)
      |> Enum.reduce({0, 0}, fn line, acc -> classify(line, acc, io, mode) end)
    after
      :ok = File.close(io)
    end
  end

  defp classify(line, {total, failed}, io, mode) do
    case Verdict.classify(Aprs.parse(line), mode) do
      :ok ->
        {total + 1, failed}

      {:failure, reason} ->
        failure = Failure.build(line, reason, seq: failed + 1)
        IO.binwrite(io, [Failure.to_json(failure), "\n"])
        {total + 1, failed + 1}
    end
  end

  # Byte-safe: a malformed line is not necessarily valid UTF-8, so the string
  # functions that assume it cannot be used here.
  defp strip_eol(line) do
    line |> strip_suffix("\n") |> strip_suffix("\r")
  end

  defp strip_suffix(binary, suffix) do
    size = byte_size(binary) - byte_size(suffix)

    if size >= 0 and binary_part(binary, size, byte_size(suffix)) == suffix do
      binary_part(binary, 0, size)
    else
      binary
    end
  end

  defp skip_line?(""), do: true
  defp skip_line?("#" <> _comment), do: true
  defp skip_line?(_line), do: false
end
