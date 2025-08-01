defmodule Aprs.TelemetryFromComment do
  @moduledoc """
  Extract telemetry data from APRS comment fields.

  Telemetry can be embedded in position comments using the format:
  |SS AAAAA BBBBB CCCCC DDDDD EEEEE FFFFF GGGGG HHHHH|
  where SS is the sequence number and A-H are telemetry values in base91.
  """

  @doc """
  Extract telemetry data from a comment field.
  Returns {telemetry_map, cleaned_comment} or {nil, original_comment}
  """
  @spec extract_telemetry_from_comment(String.t()) :: {map() | nil, String.t()}
  def extract_telemetry_from_comment(comment) when is_binary(comment) do
    # Look for telemetry pattern |...| in the comment
    case Regex.run(
           ~r/\|([!-~]{2})([!-~]{2})?([!-~]{2})?([!-~]{2})?([!-~]{2})?([!-~]{2})?([!-~]{2})?([!-~]{2})?([!-~]{2})?\|/,
           comment
         ) do
      [full_match | captures] ->
        # First capture is sequence, rest are values
        [seq_str | value_strs] = captures

        # Parse sequence from base91
        seq = parse_base91_telemetry(seq_str)

        # Parse values from base91
        vals =
          value_strs
          |> Enum.filter(&(&1 != nil && &1 != ""))
          |> Enum.map(&parse_base91_telemetry/1)

        telemetry = %{
          seq: seq,
          vals: vals
        }

        # Remove telemetry from comment
        cleaned_comment =
          comment
          |> String.replace(full_match, "")
          |> String.trim()

        {telemetry, cleaned_comment}

      _ ->
        {nil, comment}
    end
  end

  def extract_telemetry_from_comment(comment), do: {nil, comment}

  @doc """
  Parse a base91 encoded telemetry value.
  Each character has a value from 0-90 (ASCII 33-123, excluding 124).
  Two characters give a value from 0-8280.
  """
  @spec parse_base91_telemetry(String.t()) :: integer() | nil
  def parse_base91_telemetry(str) when byte_size(str) == 2 do
    <<c1::8, c2::8>> = str

    if c1 >= 33 and c1 <= 123 and c1 != 124 and
         c2 >= 33 and c2 <= 123 and c2 != 124 do
      # Convert from base91
      v1 = c1 - 33
      v2 = c2 - 33
      v1 * 91 + v2
    end
  end

  def parse_base91_telemetry(_), do: nil
end
