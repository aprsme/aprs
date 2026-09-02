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
  alias Aprs.FeedAudit.Frame
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
    mode = mode(Keyword.get(opts, :hard_errors_only, false))

    _ = Mix.Task.run("compile")

    with {:error, message} <- validate_input(input) do
      Mix.shell().error(message)
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
      |> Stream.map(&Frame.strip_eol/1)
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

  @spec mode(boolean()) :: Verdict.mode()
  defp mode(true), do: :hard
  defp mode(false), do: :all

  defp validate_input(nil), do: {:error, "Error: input file not found: (none given)"}

  defp validate_input(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "Error: input file not found: #{path}"}
    end
  end

  defp skip_line?(""), do: true
  defp skip_line?("#" <> _comment), do: true
  defp skip_line?(_line), do: false
end
