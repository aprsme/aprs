defmodule Aprs.Position do
  @moduledoc """
  Uncompressed position parsing for APRS packets.
  """

  alias Aprs.Types.Position

  @doc """
  Parse an uncompressed APRS position string. Returns a Position struct or nil.
  """
  @spec parse(String.t()) :: Position.t() | nil
  def parse(position_str) do
    # Example: "4903.50N/07201.75W>comment"
    case position_str do
      <<lat::binary-size(8), sym_table_id::binary-size(1), lon::binary-size(9), sym_code::binary-size(1),
        comment::binary>> ->
        %{latitude: lat_val, longitude: lon_val} = parse_aprs_position(lat, lon)
        ambiguity = calculate_position_ambiguity(lat, lon)
        dao_data = parse_dao_extension(comment)

        %Position{
          latitude: lat_val,
          longitude: lon_val,
          timestamp: nil,
          symbol_table_id: sym_table_id,
          symbol_code: sym_code,
          comment: comment,
          aprs_messaging?: false,
          compressed?: false,
          position_ambiguity: ambiguity,
          dao: dao_data
        }

      _ ->
        nil
    end
  end

  @doc false
  def parse_aprs_position(lat_str, lon_str) do
    import Decimal, only: [new: 1, add: 2, negate: 1]

    lat = parse_latitude(lat_str)
    lon = parse_longitude(lon_str)

    %{latitude: lat, longitude: lon}
  end

  @spec parse_latitude(String.t()) :: Decimal.t() | nil
  defp parse_latitude(lat_str) do
    case Regex.run(~r/^(\d{2})(\d{2}\.\d+)([NS])$/, lat_str) do
      [_, degrees, minutes, direction] ->
        lat_val = Decimal.add(Decimal.new(degrees), Decimal.div(Decimal.new(minutes), Decimal.new("60")))
        apply_latitude_direction(lat_val, direction)

      _ ->
        nil
    end
  end

  @spec parse_longitude(String.t()) :: Decimal.t() | nil
  defp parse_longitude(lon_str) do
    case Regex.run(~r/^(\d{3})(\d{2}\.\d+)([EW])$/, lon_str) do
      [_, degrees, minutes, direction] ->
        lon_val = Decimal.add(Decimal.new(degrees), Decimal.div(Decimal.new(minutes), Decimal.new("60")))
        apply_longitude_direction(lon_val, direction)

      _ ->
        nil
    end
  end

  @spec apply_latitude_direction(Decimal.t(), String.t()) :: Decimal.t()
  defp apply_latitude_direction(value, "S"), do: Decimal.negate(value)
  defp apply_latitude_direction(value, _), do: value

  @spec apply_longitude_direction(Decimal.t(), String.t()) :: Decimal.t()
  defp apply_longitude_direction(value, "W"), do: Decimal.negate(value)
  defp apply_longitude_direction(value, _), do: value

  @ambiguity_levels %{
    {0, 0} => 0,
    {1, 1} => 1,
    {2, 2} => 2,
    {3, 3} => 3,
    {4, 4} => 4
  }

  @doc false
  def calculate_position_ambiguity(latitude, longitude) do
    lat_spaces = count_spaces(latitude)
    lon_spaces = count_spaces(longitude)
    Map.get(@ambiguity_levels, {lat_spaces, lon_spaces}, 0)
  end

  @doc false
  def count_spaces(str) do
    str |> String.graphemes() |> Enum.count(&(&1 == " "))
  end

  @doc false
  def parse_dao_extension(comment) do
    case Regex.run(~r/!([A-Za-z])([A-Za-z])([A-Za-z])!/, comment) do
      [_, lat_dao, lon_dao, _] ->
        %{
          lat_dao: lat_dao,
          lon_dao: lon_dao,
          datum: "WGS84"
        }

      _ ->
        nil
    end
  end

  def from_aprs(lat_str, lon_str), do: parse_aprs_position(lat_str, lon_str)

  def from_decimal(lat, lon) do
    %{latitude: Decimal.new(lat), longitude: Decimal.new(lon)}
  end
end
