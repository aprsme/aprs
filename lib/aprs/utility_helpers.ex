defmodule Aprs.UtilityHelpers do
  @moduledoc """
  Utility helpers for APRS parsing using binary pattern matching.
  """

  import Aprs.Guards

  @future_tolerance_seconds 60 * 60
  @position_resolutions {18.52, 185.2, 1_852.0, 18_520.0, 185_200.0}

  @doc """
  Parses an APRS timestamp relative to the supplied UTC clock.

  Day-hour-minute timestamps which would otherwise be in the future are resolved
  against the previous month. Hour-minute-second timestamps similarly resolve
  against the previous day.
  """
  @spec parse_timestamp(String.t(), DateTime.t()) :: integer() | nil
  def parse_timestamp(time, now \\ DateTime.utc_now())

  def parse_timestamp(<<dhm::binary-size(6)>>, %DateTime{} = now) do
    parse_dhm(dhm, now)
  end

  def parse_timestamp(<<dhm::binary-size(6), suffix>>, %DateTime{} = now) when suffix in [?z, ?/] do
    parse_dhm(dhm, now)
  end

  def parse_timestamp(<<hms::binary-size(6), ?h>>, %DateTime{} = now) do
    parse_hms(hms, now)
  end

  def parse_timestamp(_, _), do: nil

  @doc """
  Parses an APRS timestamp using the current UTC time.
  """
  @spec validate_timestamp(String.t()) :: integer() | nil
  def validate_timestamp(time), do: parse_timestamp(time)

  @spec parse_dhm(binary(), DateTime.t()) :: integer() | nil
  defp parse_dhm(<<d1, d2, h1, h2, m1, m2>>, now)
       when is_digit(d1) and is_digit(d2) and is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) do
    day = decimal_pair(d1, d2)
    hour = decimal_pair(h1, h2)
    minute = decimal_pair(m1, m2)

    build_dhm_timestamp(now, day, hour, minute)
  end

  defp parse_dhm(_, _), do: nil

  @spec parse_hms(binary(), DateTime.t()) :: integer() | nil
  defp parse_hms(<<h1, h2, m1, m2, s1, s2>>, now)
       when is_digit(h1) and is_digit(h2) and is_digit(m1) and is_digit(m2) and is_digit(s1) and is_digit(s2) do
    hour = decimal_pair(h1, h2)
    minute = decimal_pair(m1, m2)
    second = decimal_pair(s1, s2)

    build_hms_timestamp(now, hour, minute, second)
  end

  defp parse_hms(_, _), do: nil

  @spec decimal_pair(byte(), byte()) :: non_neg_integer()
  defp decimal_pair(tens, ones), do: (tens - ?0) * 10 + ones - ?0

  @spec build_dhm_timestamp(DateTime.t(), integer(), integer(), integer()) :: integer() | nil
  defp build_dhm_timestamp(now, day, hour, minute)
       when day >= 1 and day <= 31 and hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 do
    case build_datetime(now.year, now.month, day, hour, minute, 0) do
      %DateTime{} = datetime ->
        if beyond_future_tolerance?(datetime, now) do
          build_previous_month_timestamp(now, day, hour, minute)
        else
          DateTime.to_unix(datetime)
        end

      nil ->
        build_previous_month_timestamp(now, day, hour, minute)
    end
  end

  defp build_dhm_timestamp(_, _, _, _), do: nil

  @spec build_previous_month_timestamp(
          DateTime.t(),
          pos_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: integer() | nil
  defp build_previous_month_timestamp(now, day, hour, minute) do
    {year, month} = previous_month(now.year, now.month)

    case build_datetime(year, month, day, hour, minute, 0) do
      %DateTime{} = datetime -> DateTime.to_unix(datetime)
      nil -> nil
    end
  end

  @spec previous_month(integer(), 1..12) :: {integer(), 1..12}
  defp previous_month(year, 1), do: {year - 1, 12}
  defp previous_month(year, month), do: {year, month - 1}

  @spec build_hms_timestamp(DateTime.t(), integer(), integer(), integer()) :: integer() | nil
  defp build_hms_timestamp(now, hour, minute, second)
       when hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 and second >= 0 and second <= 59 do
    datetime = build_datetime(now.year, now.month, now.day, hour, minute, second)

    if beyond_future_tolerance?(datetime, now) do
      datetime
      |> DateTime.shift(day: -1)
      |> DateTime.to_unix()
    else
      DateTime.to_unix(datetime)
    end
  end

  defp build_hms_timestamp(_, _, _, _), do: nil

  @spec build_datetime(
          integer(),
          1..12,
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: DateTime.t() | nil
  defp build_datetime(year, month, day, hour, minute, second) do
    with {:ok, date} <- Date.new(year, month, day),
         {:ok, time} <- Time.new(hour, minute, second),
         {:ok, datetime} <- DateTime.new(date, time) do
      datetime
    else
      _ -> nil
    end
  end

  @spec beyond_future_tolerance?(DateTime.t(), DateTime.t()) :: boolean()
  defp beyond_future_tolerance?(datetime, now) do
    DateTime.after?(datetime, DateTime.shift(now, second: @future_tolerance_seconds))
  end

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
