defmodule Aprs.Telemetry do
  @moduledoc """
  APRS telemetry parsing.
  """

  @doc """
  Parse an APRS telemetry string. Returns a struct or error.
  """
  @spec parse(String.t()) :: map() | nil
  def parse("T#" <> rest) do
    parse_telemetry_data(rest)
  end

  def parse("#" <> rest) do
    # Handle case where T is already stripped
    parse_telemetry_data(rest)
  end

  def parse(<<":PARM.", rest::binary>>) do
    %{
      data_type: :telemetry_parameters,
      parameter_names: String.split(rest, ",", trim: true),
      raw_data: rest
    }
  end

  def parse(<<":EQNS.", rest::binary>>) do
    equations =
      rest
      |> String.split(",", trim: true)
      |> Enum.chunk_every(3)
      |> Enum.map(fn [a, b, c] ->
        %{
          a: Aprs.TelemetryHelpers.parse_coefficient(a),
          b: Aprs.TelemetryHelpers.parse_coefficient(b),
          c: Aprs.TelemetryHelpers.parse_coefficient(c)
        }
      end)

    %{
      data_type: :telemetry_equations,
      equations: equations,
      raw_data: rest
    }
  end

  def parse(<<":UNIT.", rest::binary>>) do
    %{
      data_type: :telemetry_units,
      units: String.split(rest, ",", trim: true),
      raw_data: rest
    }
  end

  def parse(<<":BITS.", rest::binary>>) do
    case String.split(rest, ",", trim: true) do
      [bits_sense | project_names] ->
        %{
          data_type: :telemetry_bits,
          bits_sense: String.to_charlist(bits_sense),
          project_names: project_names,
          raw_data: rest
        }

      [] ->
        %{
          data_type: :telemetry_bits,
          bits_sense: [],
          project_names: [],
          raw_data: rest
        }
    end
  end

  def parse(data), do: %{raw_data: data, data_type: :telemetry}

  defp parse_telemetry_data(rest) do
    case String.split(rest, ",") do
      [seq | values] when length(values) >= 6 ->
        # Take first 5 as analog values
        analog_values = Enum.take(values, 5)
        # The 6th element should be the 8-bit digital value string
        bits_string = Enum.at(values, 5, "00000000")

        # Format analog values as strings with 2 decimal places
        formatted_vals =
          Enum.map(analog_values, fn val ->
            case Float.parse(val) do
              {float_val, _} -> :erlang.float_to_binary(float_val, decimals: 2)
              :error -> val
            end
          end)

        %{
          telemetry: %{
            seq: seq,
            vals: formatted_vals,
            bits: bits_string
          },
          data_type: :telemetry,
          raw_data: rest
        }

      _ ->
        %{
          raw_data: rest,
          data_type: :telemetry
        }
    end
  end
end
