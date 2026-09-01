defmodule Aprs.TelemetryFromComment do
  @moduledoc """
  Extracts base91 telemetry data from APRS comment fields.

  A telemetry block contains a sequence pair, one to five analog pairs, and,
  when all seven pairs are present, one digital pair.

  The values are base-91 counts, so `vals` holds integers in 0..8280. That is
  not the same shape as a `T#` telemetry packet, whose analog values are decimal
  text and are reported as floats by `Aprs.Telemetry`.
  """

  @base91_min 33
  @base91_max 123
  @minimum_payload_size 4
  @maximum_payload_size 14

  @doc """
  Extracts the first pipe-delimited telemetry block from a comment.

  Returns `{telemetry, cleaned_comment}` or `{nil, original_comment}`.
  """
  @spec extract_telemetry_from_comment(String.t()) :: {map() | nil, String.t()}
  def extract_telemetry_from_comment(comment) when is_binary(comment) do
    with {:ok, prefix, after_opening_pipe} <- split_at_first_pipe(comment),
         {:ok, payload, suffix} <- split_at_closing_pipe(after_opening_pipe),
         true <- valid_payload?(payload) do
      {parse_payload(payload), String.trim(prefix <> suffix)}
    else
      _invalid_or_missing_block -> {nil, comment}
    end
  end

  def extract_telemetry_from_comment(comment), do: {nil, comment}

  @doc """
  Decodes a two-byte base91 telemetry value.

  Both bytes must be in the inclusive ASCII range 33 through 123.
  """
  @spec parse_base91_telemetry(String.t()) :: integer() | nil
  def parse_base91_telemetry(<<first, second>>)
      when first >= @base91_min and first <= @base91_max and second >= @base91_min and second <= @base91_max do
    (first - @base91_min) * 91 + second - @base91_min
  end

  def parse_base91_telemetry(_value), do: nil

  @spec split_at_first_pipe(String.t()) :: {:ok, String.t(), String.t()} | :error
  defp split_at_first_pipe(comment) do
    case :binary.match(comment, "|") do
      {index, 1} ->
        suffix_start = index + 1

        {:ok, binary_part(comment, 0, index), binary_part(comment, suffix_start, byte_size(comment) - suffix_start)}

      :nomatch ->
        :error
    end
  end

  @spec split_at_closing_pipe(String.t()) :: {:ok, String.t(), String.t()} | :error
  defp split_at_closing_pipe(after_opening_pipe) do
    case :binary.match(after_opening_pipe, "|") do
      {index, 1} ->
        suffix_start = index + 1

        {:ok, binary_part(after_opening_pipe, 0, index),
         binary_part(after_opening_pipe, suffix_start, byte_size(after_opening_pipe) - suffix_start)}

      :nomatch ->
        :error
    end
  end

  @spec valid_payload?(String.t()) :: boolean()
  defp valid_payload?(payload) do
    size = byte_size(payload)

    size >= @minimum_payload_size and size <= @maximum_payload_size and
      rem(size, 2) == 0 and base91_bytes?(payload)
  end

  @spec base91_bytes?(String.t()) :: boolean()
  defp base91_bytes?(<<>>), do: true

  defp base91_bytes?(<<byte, rest::binary>>) when byte >= @base91_min and byte <= @base91_max, do: base91_bytes?(rest)

  defp base91_bytes?(_payload), do: false

  @spec parse_payload(String.t()) :: map()
  defp parse_payload(payload) do
    [sequence_pair | value_pairs] = for <<pair::binary-size(2) <- payload>>, do: pair

    if byte_size(payload) == @maximum_payload_size do
      {analog_pairs, [digital_pair]} = Enum.split(value_pairs, 5)

      %{
        seq: parse_base91_telemetry(sequence_pair),
        vals: Enum.map(analog_pairs, &parse_base91_telemetry/1),
        bits: digital_pair |> parse_base91_telemetry() |> format_bits()
      }
    else
      %{
        seq: parse_base91_telemetry(sequence_pair),
        vals: Enum.map(value_pairs, &parse_base91_telemetry/1),
        bits: nil
      }
    end
  end

  @spec format_bits(non_neg_integer()) :: String.t()
  defp format_bits(value) do
    value
    |> rem(256)
    |> Integer.to_string(2)
    |> String.pad_leading(8, "0")
  end
end
