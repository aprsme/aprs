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
    lat = parse_latitude(lat_str)
    lon = parse_longitude(lon_str)

    %{latitude: lat, longitude: lon}
  end

  @spec parse_latitude(String.t()) :: Decimal.t() | nil
  defp parse_latitude(lat_str) do
    case parse_latitude_binary(lat_str) do
      {:ok, degrees, minutes, direction} ->
        lat_val = Decimal.add(Decimal.new(degrees), Decimal.div(Decimal.new(minutes), Decimal.new("60")))
        apply_latitude_direction(lat_val, direction)

      _ ->
        nil
    end
  end

  @spec parse_longitude(String.t()) :: Decimal.t() | nil
  defp parse_longitude(lon_str) do
    case parse_longitude_binary(lon_str) do
      {:ok, degrees, minutes, direction} ->
        lon_val = Decimal.add(Decimal.new(degrees), Decimal.div(Decimal.new(minutes), Decimal.new("60")))
        apply_longitude_direction(lon_val, direction)

      _ ->
        nil
    end
  end

  # Parse latitude using binary pattern matching
  defp parse_latitude_binary(<<d1::8, d2::8, m1::8, m2::8, ?., rest::binary>>)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and m1 >= ?0 and m1 <= ?9 and m2 >= ?0 and m2 <= ?9 do
    case parse_lat_fraction_and_dir(rest) do
      {:ok, fraction, dir} ->
        degrees = <<d1, d2>>
        minutes = <<m1, m2, ?., fraction::binary>>
        {:ok, degrees, minutes, dir}

      _ ->
        :error
    end
  end

  defp parse_latitude_binary(_), do: :error

  # Parse longitude using binary pattern matching
  defp parse_longitude_binary(<<d1::8, d2::8, d3::8, m1::8, m2::8, ?., rest::binary>>)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and d3 >= ?0 and d3 <= ?9 and m1 >= ?0 and m1 <= ?9 and
              m2 >= ?0 and m2 <= ?9 do
    case parse_lon_fraction_and_dir(rest) do
      {:ok, fraction, dir} ->
        degrees = <<d1, d2, d3>>
        minutes = <<m1, m2, ?., fraction::binary>>
        {:ok, degrees, minutes, dir}

      _ ->
        :error
    end
  end

  defp parse_longitude_binary(_), do: :error

  # Parse fraction and direction for latitude
  defp parse_lat_fraction_and_dir(data), do: parse_fraction_and_dir(data, [?N, ?S])

  # Parse fraction and direction for longitude
  defp parse_lon_fraction_and_dir(data), do: parse_fraction_and_dir(data, [?E, ?W])

  # Generic fraction and direction parser
  defp parse_fraction_and_dir(data, valid_dirs) do
    parse_fraction_digits(data, <<>>, valid_dirs)
  end

  defp parse_fraction_digits(<<d::8, rest::binary>>, acc, valid_dirs) when d >= ?0 and d <= ?9 do
    parse_fraction_digits(rest, acc <> <<d>>, valid_dirs)
  end

  defp parse_fraction_digits(<<dir::8>>, acc, valid_dirs) when byte_size(acc) > 0 do
    if dir in valid_dirs do
      {:ok, acc, <<dir>>}
    else
      :error
    end
  end

  defp parse_fraction_digits(_, _, _), do: :error

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
