defmodule Aprs.WeatherHelpers do
  @moduledoc """
  Weather field extraction helpers for APRS using binary pattern matching.
  """

  @spec extract_timestamp(String.t() | binary()) :: String.t() | nil
  def extract_timestamp(data), do: extract_timestamp_scan(data)

  # Look for timestamp pattern anywhere in the data
  defp extract_timestamp_scan(<<d1::8, d2::8, d3::8, d4::8, d5::8, d6::8, marker::8, _rest::binary>>)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and d3 >= ?0 and d3 <= ?9 and d4 >= ?0 and d4 <= ?9 and
              d5 >= ?0 and d5 <= ?9 and d6 >= ?0 and d6 <= ?9 and marker in [?h, ?z, ?/, ?c] do
    <<d1, d2, d3, d4, d5, d6, marker>>
  end

  defp extract_timestamp_scan(<<_::8, rest::binary>>), do: extract_timestamp_scan(rest)
  defp extract_timestamp_scan(<<>>), do: nil

  @spec remove_timestamp(String.t() | binary()) :: binary()
  def remove_timestamp(data), do: remove_timestamp_scan(data, <<>>)

  defp remove_timestamp_scan(<<d1::8, d2::8, d3::8, d4::8, d5::8, d6::8, marker::8, rest::binary>>, acc)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and d3 >= ?0 and d3 <= ?9 and d4 >= ?0 and d4 <= ?9 and
              d5 >= ?0 and d5 <= ?9 and d6 >= ?0 and d6 <= ?9 and marker in [?h, ?z, ?/, ?c] do
    acc <> rest
  end

  defp remove_timestamp_scan(<<char::8, rest::binary>>, acc) do
    remove_timestamp_scan(rest, acc <> <<char>>)
  end

  defp remove_timestamp_scan(<<>>, acc), do: acc

  @spec parse_wind_direction(binary()) :: integer() | nil
  def parse_wind_direction(data), do: parse_wind_direction_scan(data)

  # Handle dots pattern (missing data)
  defp parse_wind_direction_scan(<<?., ?., ?., ?/, ?., ?., ?., _::binary>>), do: nil
  defp parse_wind_direction_scan(<<?/, ?., ?., ?., _::binary>>), do: nil

  # Handle 3-digit wind direction with slash
  defp parse_wind_direction_scan(<<d1::8, d2::8, d3::8, ?/, _::binary>>)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and d3 >= ?0 and d3 <= ?9 do
    (d1 - ?0) * 100 + (d2 - ?0) * 10 + (d3 - ?0)
  end

  # Handle 3-digit wind direction followed by 's' (for positionless format)
  defp parse_wind_direction_scan(<<d1::8, d2::8, d3::8, ?s, _::binary>>)
       when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 and d3 >= ?0 and d3 <= ?9 do
    (d1 - ?0) * 100 + (d2 - ?0) * 10 + (d3 - ?0)
  end

  # Handle 2-digit wind direction
  defp parse_wind_direction_scan(<<d1::8, d2::8, ?/, _::binary>>) when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 do
    (d1 - ?0) * 10 + (d2 - ?0)
  end

  # Handle 1-digit wind direction
  defp parse_wind_direction_scan(<<d1::8, ?/, _::binary>>) when d1 >= ?0 and d1 <= ?9 do
    d1 - ?0
  end

  defp parse_wind_direction_scan(<<_::8, rest::binary>>), do: parse_wind_direction_scan(rest)
  defp parse_wind_direction_scan(<<>>), do: nil

  @spec parse_wind_speed(binary()) :: integer() | nil
  def parse_wind_speed(data), do: parse_wind_speed_scan(data)

  defp parse_wind_speed_scan(<<?/, s1::8, s2::8, s3::8, _::binary>>)
       when s1 >= ?0 and s1 <= ?9 and s2 >= ?0 and s2 <= ?9 and s3 >= ?0 and s3 <= ?9 do
    (s1 - ?0) * 100 + (s2 - ?0) * 10 + (s3 - ?0)
  end

  # Also handle 's' prefix for wind speed (sustained wind)
  defp parse_wind_speed_scan(<<?s, s1::8, s2::8, s3::8, _::binary>>)
       when s1 >= ?0 and s1 <= ?9 and s2 >= ?0 and s2 <= ?9 and s3 >= ?0 and s3 <= ?9 do
    (s1 - ?0) * 100 + (s2 - ?0) * 10 + (s3 - ?0)
  end

  defp parse_wind_speed_scan(<<_::8, rest::binary>>), do: parse_wind_speed_scan(rest)
  defp parse_wind_speed_scan(<<>>), do: nil

  @spec parse_wind_gust(binary()) :: integer() | nil
  def parse_wind_gust(data), do: parse_wind_gust_scan(data)

  defp parse_wind_gust_scan(<<?g, g1::8, g2::8, g3::8, _::binary>>)
       when g1 >= ?0 and g1 <= ?9 and g2 >= ?0 and g2 <= ?9 and g3 >= ?0 and g3 <= ?9 do
    (g1 - ?0) * 100 + (g2 - ?0) * 10 + (g3 - ?0)
  end

  defp parse_wind_gust_scan(<<_::8, rest::binary>>), do: parse_wind_gust_scan(rest)
  defp parse_wind_gust_scan(<<>>), do: nil

  @spec parse_temperature(binary()) :: integer() | nil
  def parse_temperature(data), do: parse_temperature_scan(data)

  # Handle negative temperature with minus sign
  defp parse_temperature_scan(<<?t, ?-, t1::8, t2::8, t3::8, _::binary>>)
       when t1 >= ?0 and t1 <= ?9 and t2 >= ?0 and t2 <= ?9 and t3 >= ?0 and t3 <= ?9 do
    -((t1 - ?0) * 100 + (t2 - ?0) * 10 + (t3 - ?0))
  end

  # Handle negative temperature with minus sign and 2 digits
  defp parse_temperature_scan(<<?t, ?-, t1::8, t2::8, _::binary>>) when t1 >= ?0 and t1 <= ?9 and t2 >= ?0 and t2 <= ?9 do
    -((t1 - ?0) * 10 + (t2 - ?0))
  end

  # Handle negative temperature with minus sign and 1 digit
  defp parse_temperature_scan(<<?t, ?-, t1::8, _::binary>>) when t1 >= ?0 and t1 <= ?9 do
    -(t1 - ?0)
  end

  # Handle malformed negative temperature (like t0-1)
  defp parse_temperature_scan(<<?t, d1::8, ?-, d2::8, _::binary>>) when d1 >= ?0 and d1 <= ?9 and d2 >= ?0 and d2 <= ?9 do
    # Parse as -d2 (ignore the leading digit)
    -(d2 - ?0)
  end

  # Handle positive temperature
  defp parse_temperature_scan(<<?t, t1::8, t2::8, t3::8, _::binary>>)
       when t1 >= ?0 and t1 <= ?9 and t2 >= ?0 and t2 <= ?9 and t3 >= ?0 and t3 <= ?9 do
    (t1 - ?0) * 100 + (t2 - ?0) * 10 + (t3 - ?0)
  end

  defp parse_temperature_scan(<<_::8, rest::binary>>), do: parse_temperature_scan(rest)
  defp parse_temperature_scan(<<>>), do: nil

  @spec parse_rainfall_1h(binary()) :: float() | nil
  def parse_rainfall_1h(data), do: parse_rainfall_1h_scan(data)

  defp parse_rainfall_1h_scan(<<?r, r1::8, r2::8, r3::8, _::binary>>)
       when r1 >= ?0 and r1 <= ?9 and r2 >= ?0 and r2 <= ?9 and r3 >= ?0 and r3 <= ?9 do
    ((r1 - ?0) * 100 + (r2 - ?0) * 10 + (r3 - ?0)) / 100.0
  end

  defp parse_rainfall_1h_scan(<<_::8, rest::binary>>), do: parse_rainfall_1h_scan(rest)
  defp parse_rainfall_1h_scan(<<>>), do: nil

  @spec parse_rainfall_24h(binary()) :: float() | nil
  def parse_rainfall_24h(data), do: parse_rainfall_24h_scan(data)

  defp parse_rainfall_24h_scan(<<?p, p1::8, p2::8, p3::8, _::binary>>)
       when p1 >= ?0 and p1 <= ?9 and p2 >= ?0 and p2 <= ?9 and p3 >= ?0 and p3 <= ?9 do
    ((p1 - ?0) * 100 + (p2 - ?0) * 10 + (p3 - ?0)) / 100.0
  end

  defp parse_rainfall_24h_scan(<<_::8, rest::binary>>), do: parse_rainfall_24h_scan(rest)
  defp parse_rainfall_24h_scan(<<>>), do: nil

  @spec parse_rainfall_since_midnight(binary()) :: float() | nil
  def parse_rainfall_since_midnight(data), do: parse_rainfall_since_midnight_scan(data)

  defp parse_rainfall_since_midnight_scan(<<?P, p1::8, p2::8, p3::8, _::binary>>)
       when p1 >= ?0 and p1 <= ?9 and p2 >= ?0 and p2 <= ?9 and p3 >= ?0 and p3 <= ?9 do
    ((p1 - ?0) * 100 + (p2 - ?0) * 10 + (p3 - ?0)) / 100.0
  end

  defp parse_rainfall_since_midnight_scan(<<_::8, rest::binary>>), do: parse_rainfall_since_midnight_scan(rest)

  defp parse_rainfall_since_midnight_scan(<<>>), do: nil

  @spec parse_humidity(binary()) :: integer() | nil
  def parse_humidity(data), do: parse_humidity_scan(data)

  defp parse_humidity_scan(<<?h, h1::8, h2::8, _::binary>>) when h1 >= ?0 and h1 <= ?9 and h2 >= ?0 and h2 <= ?9 do
    humidity = (h1 - ?0) * 10 + (h2 - ?0)
    normalize_humidity(humidity)
  end

  defp parse_humidity_scan(<<_::8, rest::binary>>), do: parse_humidity_scan(rest)
  defp parse_humidity_scan(<<>>), do: nil

  defp normalize_humidity(0), do: 100
  defp normalize_humidity(val), do: val

  @spec parse_pressure(binary()) :: float() | nil
  def parse_pressure(data), do: parse_pressure_scan(data)

  defp parse_pressure_scan(<<?b, b1::8, b2::8, b3::8, b4::8, b5::8, _::binary>>)
       when b1 >= ?0 and b1 <= ?9 and b2 >= ?0 and b2 <= ?9 and b3 >= ?0 and b3 <= ?9 and b4 >= ?0 and b4 <= ?9 and
              b5 >= ?0 and b5 <= ?9 do
    ((b1 - ?0) * 10_000 + (b2 - ?0) * 1000 + (b3 - ?0) * 100 + (b4 - ?0) * 10 + (b5 - ?0)) / 10.0
  end

  defp parse_pressure_scan(<<_::8, rest::binary>>), do: parse_pressure_scan(rest)
  defp parse_pressure_scan(<<>>), do: nil

  @spec parse_luminosity(binary()) :: integer() | nil
  def parse_luminosity(data), do: parse_luminosity_scan(data)

  defp parse_luminosity_scan(<<marker::8, l1::8, l2::8, l3::8, _::binary>>)
       when marker in [?l, ?L] and l1 >= ?0 and l1 <= ?9 and l2 >= ?0 and l2 <= ?9 and l3 >= ?0 and l3 <= ?9 do
    (l1 - ?0) * 100 + (l2 - ?0) * 10 + (l3 - ?0)
  end

  defp parse_luminosity_scan(<<_::8, rest::binary>>), do: parse_luminosity_scan(rest)
  defp parse_luminosity_scan(<<>>), do: nil

  @spec parse_snow(binary()) :: float() | nil
  def parse_snow(data), do: parse_snow_scan(data)

  defp parse_snow_scan(<<?s, s1::8, s2::8, s3::8, _::binary>>)
       when s1 >= ?0 and s1 <= ?9 and s2 >= ?0 and s2 <= ?9 and s3 >= ?0 and s3 <= ?9 do
    ((s1 - ?0) * 100 + (s2 - ?0) * 10 + (s3 - ?0)) / 10.0
  end

  defp parse_snow_scan(<<_::8, rest::binary>>), do: parse_snow_scan(rest)
  defp parse_snow_scan(<<>>), do: nil
end
