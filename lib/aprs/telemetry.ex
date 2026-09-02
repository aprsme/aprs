defmodule Aprs.Telemetry do
  @moduledoc """
  APRS telemetry parsing.
  """

  alias Aprs.TelemetryHelpers

  @doc """
  Parses APRS telemetry data or a colon-prefixed telemetry definition.
  """
  @spec parse(String.t()) :: map()
  def parse("T#" <> rest), do: parse_telemetry_data(rest)
  def parse("#" <> rest), do: parse_telemetry_data(rest)
  def parse(<<":PARM.", rest::binary>>), do: parse_definition("PARM." <> rest)
  def parse(<<":UNIT.", rest::binary>>), do: parse_definition("UNIT." <> rest)
  def parse(<<":EQNS.", rest::binary>>), do: parse_definition("EQNS." <> rest)
  def parse(<<":BITS.", rest::binary>>), do: parse_definition("BITS." <> rest)
  def parse(data), do: %{raw_data: data, data_type: :telemetry}

  @doc """
  Parses a PARM, UNIT, EQNS, or BITS telemetry definition.

  A leading colon is optional. EQNS definitions discard coefficients in a
  trailing group that contains fewer than three coefficients.
  """
  @spec parse_definition(String.t()) :: map() | nil
  def parse_definition(":PARM." <> rest), do: parse_definition("PARM." <> rest)
  def parse_definition(":UNIT." <> rest), do: parse_definition("UNIT." <> rest)
  def parse_definition(":EQNS." <> rest), do: parse_definition("EQNS." <> rest)
  def parse_definition(":BITS." <> rest), do: parse_definition("BITS." <> rest)

  def parse_definition("PARM." <> rest) do
    %{
      data_type: :telemetry_parameters,
      parameter_names: String.split(rest, ",", trim: true),
      raw_data: rest
    }
  end

  def parse_definition("UNIT." <> rest) do
    %{
      data_type: :telemetry_units,
      units: String.split(rest, ",", trim: true),
      raw_data: rest
    }
  end

  def parse_definition("EQNS." <> rest) do
    equations =
      rest
      |> String.split(",", trim: true)
      |> Enum.chunk_every(3, 3, :discard)
      |> Enum.map(fn [a, b, c] ->
        %{
          a: TelemetryHelpers.parse_coefficient(a),
          b: TelemetryHelpers.parse_coefficient(b),
          c: TelemetryHelpers.parse_coefficient(c)
        }
      end)

    %{
      data_type: :telemetry_equations,
      equations: equations,
      raw_data: rest
    }
  end

  def parse_definition("BITS." <> rest) do
    rest
    |> String.split(",", trim: true)
    |> parse_bits_data(rest)
  end

  def parse_definition(_definition), do: nil

  @spec parse_bits_data([String.t()], String.t()) :: map()
  defp parse_bits_data([bits_sense | project_names], rest) do
    %{
      data_type: :telemetry_bits,
      bits_sense: String.to_charlist(bits_sense),
      project_names: project_names,
      raw_data: rest
    }
  end

  defp parse_bits_data([], rest) do
    %{
      data_type: :telemetry_bits,
      bits_sense: [],
      project_names: [],
      raw_data: rest
    }
  end

  @spec parse_telemetry_data(String.t()) :: map()
  defp parse_telemetry_data(rest) do
    case String.split(rest, ",") do
      [_sequence] ->
        %{raw_data: rest, data_type: :telemetry}

      [sequence | values] ->
        {analog_values, bits} = split_telemetry_values(values)

        maybe_put_mbits(
          %{
            telemetry: %{seq: sequence, vals: Enum.map(analog_values, &parse_analog_value/1), bits: bits},
            data_type: :telemetry,
            raw_data: rest
          },
          bits
        )
    end
  end

  @spec split_telemetry_values([String.t()]) :: {[String.t()], String.t() | nil}
  defp split_telemetry_values(values) do
    values = Enum.take(values, 6)

    case Enum.split(values, 5) do
      {analog_values, [bits]} ->
        {analog_values, valid_bits_or_nil(bits)}

      {values, []} ->
        split_optional_bits(values)
    end
  end

  # The caller always has at least one value here, so the list is never empty.
  @spec split_optional_bits([String.t()]) :: {[String.t()], String.t() | nil}
  defp split_optional_bits(values) do
    {last_value, analog_values} = List.pop_at(values, -1)

    if digital_bits?(last_value), do: {analog_values, last_value}, else: {values, nil}
  end

  @spec valid_bits_or_nil(String.t()) :: String.t() | nil
  defp valid_bits_or_nil(bits) do
    if digital_bits?(bits), do: bits
  end

  @spec digital_bits?(String.t()) :: boolean()
  defp digital_bits?(bits) when byte_size(bits) == 8, do: digital_bits_bytes?(bits)
  defp digital_bits?(_bits), do: false

  @spec digital_bits_bytes?(String.t()) :: boolean()
  defp digital_bits_bytes?(<<>>), do: true
  defp digital_bits_bytes?(<<bit, rest::binary>>) when bit in [?0, ?1], do: digital_bits_bytes?(rest)
  defp digital_bits_bytes?(_bits), do: false

  @spec parse_analog_value(String.t()) :: float() | nil
  defp parse_analog_value(value) do
    case Float.parse(value) do
      {number, _remainder} -> number
      :error -> nil
    end
  end

  @spec maybe_put_mbits(map(), String.t() | nil) :: map()
  defp maybe_put_mbits(result, nil), do: result
  defp maybe_put_mbits(result, bits), do: Map.put(result, :mbits, bits)
end
