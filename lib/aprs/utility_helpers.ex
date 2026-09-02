defmodule Aprs.UtilityHelpers do
  @moduledoc """
  Utility helpers for APRS parsing using binary pattern matching.
  """

  import Aprs.Guards

  @future_tolerance_seconds 60 * 60
  @seconds_per_day 86_400
  @unix_epoch_gregorian_seconds 62_167_219_200
  @position_resolutions {18.52, 185.2, 1_852.0, 18_520.0, 185_200.0}

  @doc """
  Parses an APRS timestamp relative to the supplied UTC clock.

  Day-hour-minute timestamps which would otherwise be in the future are resolved
  against the previous month. Hour-minute-second timestamps similarly resolve
  against the previous day.
  """
  @spec parse_timestamp(String.t(), DateTime.t()) :: integer() | nil
  def parse_timestamp(time, now \\ Aprs.Clock.utc_now())

  def parse_timestamp(<<dhm::binary-size(6)>>, %DateTime{year: year, month: month} = now) do
    parse_dhm(dhm, year, month, DateTime.to_unix(now))
  end

  def parse_timestamp(<<dhm::binary-size(6), suffix>>, %DateTime{year: year, month: month} = now)
      when suffix in [?z, ?/] do
    parse_dhm(dhm, year, month, DateTime.to_unix(now))
  end

  def parse_timestamp(<<hms::binary-size(6), ?h>>, %DateTime{year: year, month: month, day: day} = now) do
    parse_hms(hms, year, month, day, DateTime.to_unix(now))
  end

  def parse_timestamp(_, _), do: nil

  @doc """
  Parses an APRS timestamp using the current UTC time.
  """
  @spec validate_timestamp(String.t()) :: integer() | nil
  def validate_timestamp(time), do: parse_timestamp(time)

  @spec parse_dhm(binary(), integer(), 1..12, integer()) :: integer() | nil
  defp parse_dhm(<<d1, d2, h1, h2, m1, m2>>, year, month, now_unix)
       when is_digit(d1) and is_digit(d2) and is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) do
    day = decimal_pair(d1, d2)
    hour = decimal_pair(h1, h2)
    minute = decimal_pair(m1, m2)

    build_dhm_timestamp(year, month, now_unix, day, hour, minute)
  end

  defp parse_dhm(_, _, _, _), do: nil

  @spec parse_hms(binary(), integer(), 1..12, 1..31, integer()) :: integer() | nil
  defp parse_hms(<<h1, h2, m1, m2, s1, s2>>, year, month, day, now_unix)
       when is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) and is_digit(s1) and is_digit(s2) do
    hour = decimal_pair(h1, h2)
    minute = decimal_pair(m1, m2)
    second = decimal_pair(s1, s2)

    build_hms_timestamp(year, month, day, now_unix, hour, minute, second)
  end

  defp parse_hms(_, _, _, _, _), do: nil

  @spec decimal_pair(byte(), byte()) :: non_neg_integer()
  defp decimal_pair(tens, ones), do: (tens - ?0) * 10 + ones - ?0

  @spec build_dhm_timestamp(integer(), 1..12, integer(), integer(), integer(), integer()) ::
          integer() | nil
  defp build_dhm_timestamp(year, month, now_unix, day, hour, minute)
       when day >= 1 and day <= 31 and hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 do
    case build_unix_timestamp(year, month, day, hour, minute, 0) do
      timestamp when is_integer(timestamp) and timestamp <= now_unix + @future_tolerance_seconds ->
        timestamp

      # A day this month does not have, or one still to come, is last month's.
      _future_or_invalid ->
        build_previous_month_timestamp(year, month, day, hour, minute)
    end
  end

  defp build_dhm_timestamp(_, _, _, _, _, _), do: nil

  @spec build_previous_month_timestamp(
          integer(),
          1..12,
          pos_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: integer() | nil
  defp build_previous_month_timestamp(year, month, day, hour, minute) do
    {previous_year, previous_month} = previous_month(year, month)
    build_unix_timestamp(previous_year, previous_month, day, hour, minute, 0)
  end

  @spec previous_month(integer(), 1..12) :: {integer(), 1..12}
  defp previous_month(year, 1), do: {year - 1, 12}
  defp previous_month(year, month), do: {year, month - 1}

  @spec build_hms_timestamp(integer(), 1..12, 1..31, integer(), integer(), integer(), integer()) ::
          integer() | nil
  defp build_hms_timestamp(year, month, day, now_unix, hour, minute, second)
       when hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 and second >= 0 and second <= 59 do
    year
    |> build_unix_timestamp(month, day, hour, minute, second)
    |> resolve_hms_timestamp(now_unix)
  end

  defp build_hms_timestamp(_, _, _, _, _, _, _), do: nil

  @spec resolve_hms_timestamp(integer(), integer()) :: integer()
  defp resolve_hms_timestamp(timestamp, now_unix) when timestamp > now_unix + @future_tolerance_seconds do
    timestamp - @seconds_per_day
  end

  defp resolve_hms_timestamp(timestamp, _now_unix), do: timestamp

  @spec build_unix_timestamp(
          integer(),
          1..12,
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: integer() | nil
  defp build_unix_timestamp(year, month, day, hour, minute, second) do
    build_unix_timestamp(
      year,
      month,
      day,
      hour,
      minute,
      second,
      :calendar.valid_date(year, month, day)
    )
  end

  @spec build_unix_timestamp(
          integer(),
          1..12,
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          boolean()
        ) :: integer() | nil
  defp build_unix_timestamp(year, month, day, hour, minute, second, true) do
    :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}}) -
      @unix_epoch_gregorian_seconds
  end

  defp build_unix_timestamp(_, _, _, _, _, _, false), do: nil

  @doc """
  Returns the latitude-derived resolution in metres for an APRS ambiguity level.
  """
  @spec position_resolution(non_neg_integer()) :: float()
  def position_resolution(ambiguity) when ambiguity in 0..4 do
    elem(@position_resolutions, ambiguity)
  end

  def position_resolution(_), do: 18.52

  @doc """
  Returns the resolution in metres for a compressed APRS position.
  """
  @spec compressed_position_resolution() :: float()
  def compressed_position_resolution, do: 0.291

  @doc """
  Returns the resolution in metres for an NMEA position.
  """
  @spec nmea_position_resolution() :: float()
  def nmea_position_resolution, do: 0.1852

  @doc """
  Counts leading closing braces in a string.
  """
  @spec count_leading_braces(String.t()) :: non_neg_integer()
  def count_leading_braces(str) when is_binary(str) do
    count_leading_braces_binary(str, 0)
  end

  def count_leading_braces(_), do: 0

  @spec count_leading_braces_binary(binary(), non_neg_integer()) :: non_neg_integer()
  defp count_leading_braces_binary(<<?}, rest::binary>>, count) do
    count_leading_braces_binary(rest, count + 1)
  end

  defp count_leading_braces_binary(_, count), do: count
end
