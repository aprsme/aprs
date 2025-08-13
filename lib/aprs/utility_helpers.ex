defmodule Aprs.UtilityHelpers do
  @moduledoc """
  Utility helpers for APRS parsing using binary pattern matching.
  """

  @spec safe_string_conversion(binary() | nil, any()) :: String.t()
  def safe_string_conversion(nil, default), do: default
  def safe_string_conversion("", default), do: default

  def safe_string_conversion(value, _default) when is_binary(value) do
    # Clean control characters but keep valid UTF-8
    value
    |> String.to_charlist()
    |> Enum.filter(&(&1 >= 32 or &1 == 9 or &1 == 10 or &1 == 13))
    |> List.to_string()
    |> String.trim()
  rescue
    _ -> ""
  end

  def safe_string_conversion(value, default) when is_list(value) do
    case List.to_string(value) do
      "" -> default
      str -> safe_string_conversion(str, default)
    end
  rescue
    _ -> default
  end

  def safe_string_conversion(_value, default), do: default

  @spec clean_string(String.t() | nil) :: String.t()
  def clean_string(nil), do: ""
  def clean_string(""), do: ""

  def clean_string(str) when is_binary(str) do
    # Clean control characters but keep valid UTF-8
    str
    |> String.to_charlist()
    |> Enum.filter(&(&1 >= 32 or &1 == 9 or &1 == 10 or &1 == 13))
    |> List.to_string()
    |> String.trim()
  rescue
    _ -> ""
  end

  def clean_string(_), do: ""

  @spec find_matches(String.t(), Regex.t()) :: [String.t()]
  def find_matches(data, regex) when is_binary(data) do
    case Regex.run(regex, data, capture: :all_but_first) do
      nil -> []
      matches -> matches
    end
  end

  def find_matches(_, _), do: []

  @spec extract_value(String.t(), Regex.t()) :: String.t() | nil
  def extract_value(data, regex) do
    case Regex.run(regex, data) do
      [_, value] -> value
      _ -> nil
    end
  end

  @spec extract_values(String.t(), Regex.t()) :: [String.t()]
  def extract_values(data, regex) do
    case Regex.run(regex, data, capture: :all_but_first) do
      nil -> []
      values -> values
    end
  end

  @spec validate_position_data(String.t(), String.t()) ::
          {:ok, {Decimal.t(), Decimal.t()}} | {:error, :invalid_position}
  def validate_position_data(latitude, longitude) do
    lat =
      case parse_latitude_binary(latitude) do
        {:ok, degrees, minutes, direction} ->
          lat_val = Decimal.add(Decimal.new(degrees), Decimal.div(Decimal.new(minutes), Decimal.new("60")))
          apply_latitude_direction(lat_val, direction)

        _ ->
          nil
      end

    lon =
      case parse_longitude_binary(longitude) do
        {:ok, degrees, minutes, direction} ->
          lon_val = Decimal.add(Decimal.new(degrees), Decimal.div(Decimal.new(minutes), Decimal.new("60")))
          apply_longitude_direction(lon_val, direction)

        _ ->
          nil
      end

    validate_coordinates(lat, lon)
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

  @spec validate_coordinates(Decimal.t() | nil, Decimal.t() | nil) ::
          {:ok, {Decimal.t(), Decimal.t()}} | {:error, :invalid_position}
  defp validate_coordinates(%Decimal{} = lat, %Decimal{} = lon), do: {:ok, {lat, lon}}
  defp validate_coordinates(_, _), do: {:error, :invalid_position}

  @spec validate_timestamp(String.t()) :: integer() | nil
  def validate_timestamp(time) when is_binary(time) do
    # Parse APRS timestamp formats based on length
    case byte_size(time) do
      6 -> parse_dhm_format(time)
      7 -> parse_7_char_format(time)
      _ -> nil
    end
  end

  def validate_timestamp(_), do: nil

  # Parse DHM format (day/hour/minute) using binary pattern matching
  defp parse_dhm_format(<<d1::8, d2::8, h1::8, h2::8, m1::8, m2::8>>)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and h1 >= ?0 and h1 <= ?9 and h2 >= ?0 and h2 <= ?9 and
              m1 >= ?0 and m1 <= ?9 and m2 >= ?0 and m2 <= ?9 do
    day = (d1 - ?0) * 10 + (d2 - ?0)
    hour = (h1 - ?0) * 10 + (h2 - ?0)
    minute = (m1 - ?0) * 10 + (m2 - ?0)
    build_timestamp_from_dhm_int(day, hour, minute)
  end

  defp parse_dhm_format(_), do: nil

  defp build_timestamp_from_dhm_int(day, hour, minute) do
    now = DateTime.utc_now()
    build_timestamp_if_valid_dhm(now, day, hour, minute)
  end

  @spec build_timestamp_if_valid_dhm(DateTime.t(), integer(), integer(), integer()) :: integer() | nil
  defp build_timestamp_if_valid_dhm(now, day, hour, minute)
       when day >= 1 and day <= 31 and hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 do
    case Date.new(now.year, now.month, day) do
      {:ok, date} ->
        {:ok, time} = Time.new(hour, minute, 0)
        {:ok, datetime} = DateTime.new(date, time)
        DateTime.to_unix(datetime)

      _ ->
        nil
    end
  end

  defp build_timestamp_if_valid_dhm(_, _, _, _), do: nil

  # Parse 7-character format (HMS or Zulu)
  defp parse_7_char_format(time) do
    case time do
      <<_::binary-size(6), ?h>> -> parse_hms_format(time)
      <<_::binary-size(6), ?z>> -> parse_zulu_format(time)
      _ -> nil
    end
  end

  # Parse HMS format (hour/minute/second) using binary pattern matching
  defp parse_hms_format(<<h1::8, h2::8, m1::8, m2::8, s1::8, s2::8, ?h>>)
       when h1 >= ?0 and h1 <= ?9 and h2 >= ?0 and h2 <= ?9 and m1 >= ?0 and m1 <= ?9 and m2 >= ?0 and m2 <= ?9 and
              s1 >= ?0 and s1 <= ?9 and s2 >= ?0 and s2 <= ?9 do
    hour = (h1 - ?0) * 10 + (h2 - ?0)
    minute = (m1 - ?0) * 10 + (m2 - ?0)
    second = (s1 - ?0) * 10 + (s2 - ?0)
    build_timestamp_if_valid_hms(hour, minute, second)
  end

  defp parse_hms_format(_), do: nil

  @spec build_timestamp_if_valid_hms(integer(), integer(), integer()) :: integer() | nil
  defp build_timestamp_if_valid_hms(hour, minute, second)
       when hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 and second >= 0 and second <= 59 do
    {:ok, time} = Time.new(hour, minute, second)
    {:ok, datetime} = DateTime.new(Date.utc_today(), time)
    DateTime.to_unix(datetime)
  end

  defp build_timestamp_if_valid_hms(_, _, _), do: nil

  # Parse Zulu format (day/hour/minute) using binary pattern matching
  defp parse_zulu_format(<<d1::8, d2::8, h1::8, h2::8, m1::8, m2::8, ?z>>)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and h1 >= ?0 and h1 <= ?9 and h2 >= ?0 and h2 <= ?9 and
              m1 >= ?0 and m1 <= ?9 and m2 >= ?0 and m2 <= ?9 do
    day = (d1 - ?0) * 10 + (d2 - ?0)
    hour = (h1 - ?0) * 10 + (h2 - ?0)
    minute = (m1 - ?0) * 10 + (m2 - ?0)
    build_timestamp_from_dhm_int(day, hour, minute)
  end

  defp parse_zulu_format(_), do: nil

  @doc """
  Calculate position resolution in meters based on ambiguity level.
  """
  @spec position_resolution(integer()) :: integer()
  def position_resolution(ambiguity) when ambiguity in 0..4 do
    case ambiguity do
      # ~18.52 meters
      0 -> 19
      # ~185.2 meters  
      1 -> 185
      # ~1.852 km
      2 -> 1852
      # ~18.52 km
      3 -> 18_520
      # ~185.2 km
      4 -> 185_200
    end
  end

  # Default to highest resolution
  def position_resolution(_), do: 19

  @doc """
  Format DAO extension for display.
  """
  @spec format_dao(String.t() | nil) :: String.t()
  def format_dao(nil), do: ""
  def format_dao(dao) when is_binary(dao), do: "!#{dao}!"
  def format_dao(_), do: ""

  @doc """
  Count spaces in a string.
  """
  @spec count_spaces(String.t()) :: integer()
  def count_spaces(str) when is_binary(str) do
    str
    |> String.to_charlist()
    |> Enum.count(&(&1 == ?\s))
  end

  def count_spaces(_), do: 0

  @doc """
  Count leading braces (}) in a string.
  """
  @spec count_leading_braces(String.t()) :: integer()
  def count_leading_braces(str) when is_binary(str) do
    count_leading_braces_binary(str, 0)
  end

  def count_leading_braces(_), do: 0

  defp count_leading_braces_binary(<<?}, rest::binary>>, count) do
    count_leading_braces_binary(rest, count + 1)
  end

  defp count_leading_braces_binary(_, count), do: count

  @doc """
  Calculate position ambiguity based on leading spaces.
  """
  @spec calculate_position_ambiguity(String.t(), String.t()) :: integer()
  def calculate_position_ambiguity(lat, lon) when is_binary(lat) and is_binary(lon) do
    lat_spaces = count_leading_spaces(lat)
    lon_spaces = count_leading_spaces(lon)

    # Return 0 if spaces don't match or if more than 4 spaces
    if lat_spaces != lon_spaces or lat_spaces > 4 do
      0
    else
      lat_spaces
    end
  end

  def calculate_position_ambiguity(_, _), do: 0

  defp count_leading_spaces(str) when is_binary(str) do
    count_leading_spaces_binary(str, 0)
  end

  defp count_leading_spaces(_), do: 0

  defp count_leading_spaces_binary(<<32, rest::binary>>, count) do
    count_leading_spaces_binary(rest, count + 1)
  end

  defp count_leading_spaces_binary(_, count), do: count

  @doc """
  Calculate position resolution based on ambiguity.
  """
  @spec calculate_position_resolution(integer()) :: integer()
  def calculate_position_resolution(ambiguity), do: position_resolution(ambiguity)

  @doc """
  Calculate compressed position resolution.
  """
  @spec calculate_compressed_position_resolution() :: float()
  def calculate_compressed_position_resolution do
    # Compressed position has approximately 0.291 meters resolution
    0.291
  end
end
