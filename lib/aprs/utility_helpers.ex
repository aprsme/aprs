defmodule Aprs.UtilityHelpers do
  @moduledoc """
  Utility helpers for APRS parsing using binary pattern matching.
  """

  import Aprs.Guards

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
  @spec parse_dhm_format(binary()) :: integer() | nil
  defp parse_dhm_format(<<d1::8, d2::8, h1::8, h2::8, m1::8, m2::8>>)
       when is_digit(d1) and is_digit(d2) and is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) do
    day = (d1 - ?0) * 10 + (d2 - ?0)
    hour = (h1 - ?0) * 10 + (h2 - ?0)
    minute = (m1 - ?0) * 10 + (m2 - ?0)
    build_timestamp_from_dhm_int(day, hour, minute)
  end

  defp parse_dhm_format(_), do: nil

  @spec build_timestamp_from_dhm_int(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: integer() | nil
  defp build_timestamp_from_dhm_int(day, hour, minute) do
    now = DateTime.utc_now()
    build_timestamp_if_valid_dhm(now, day, hour, minute)
  end

  @spec build_timestamp_if_valid_dhm(DateTime.t(), integer(), integer(), integer()) :: integer() | nil
  defp build_timestamp_if_valid_dhm(now, day, hour, minute)
       when day >= 1 and hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 do
    if day <= Calendar.ISO.days_in_month(now.year, now.month) do
      {:ok, date} = Date.new(now.year, now.month, day)
      {:ok, time} = Time.new(hour, minute, 0)
      {:ok, datetime} = DateTime.new(date, time)
      DateTime.to_unix(datetime)
    end
  end

  defp build_timestamp_if_valid_dhm(_, _, _, _), do: nil

  # Parse 7-character format (HMS or Zulu)
  @spec parse_7_char_format(binary()) :: integer() | nil
  defp parse_7_char_format(time) do
    case time do
      <<_::binary-size(6), ?h>> -> parse_hms_format(time)
      <<_::binary-size(6), ?z>> -> parse_zulu_format(time)
      _ -> nil
    end
  end

  # Parse HMS format (hour/minute/second) using binary pattern matching
  @spec parse_hms_format(binary()) :: integer() | nil
  defp parse_hms_format(<<h1::8, h2::8, m1::8, m2::8, s1::8, s2::8, ?h>>)
       when is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) and is_digit(s1) and is_digit(s2) do
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
  @spec parse_zulu_format(binary()) :: integer() | nil
  defp parse_zulu_format(<<d1::8, d2::8, h1::8, h2::8, m1::8, m2::8, ?z>>)
       when is_digit(d1) and is_digit(d2) and is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) do
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
  Count spaces in a string. Delegates to `Aprs.Position.count_spaces/1`.
  """
  @spec count_spaces(String.t()) :: non_neg_integer()
  def count_spaces(str) when is_binary(str), do: Aprs.Position.count_spaces(str)
  def count_spaces(_), do: 0

  @doc """
  Count leading braces (}) in a string.
  """
  @spec count_leading_braces(String.t()) :: integer()
  def count_leading_braces(str) when is_binary(str) do
    count_leading_braces_binary(str, 0)
  end

  def count_leading_braces(_), do: 0

  @spec count_leading_braces_binary(binary(), non_neg_integer()) :: non_neg_integer()
  defp count_leading_braces_binary(<<?}, rest::binary>>, count) do
    count_leading_braces_binary(rest, count + 1)
  end

  defp count_leading_braces_binary(_, count), do: count

  @doc """
  Calculate position ambiguity based on spaces in coordinate strings.
  Delegates to `Aprs.Position.calculate_position_ambiguity/2`.
  """
  @spec calculate_position_ambiguity(String.t(), String.t()) :: non_neg_integer()
  def calculate_position_ambiguity(lat, lon), do: Aprs.Position.calculate_position_ambiguity(lat, lon)

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
