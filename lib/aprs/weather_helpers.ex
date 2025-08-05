defmodule Aprs.WeatherHelpers do
  @moduledoc """
  Weather field extraction helpers for APRS.
  """

  # Helper function to extract regex capture or return nil
  defp extract_regex_value(pattern, data, extractor \\ & &1) do
    case Regex.run(pattern, data) do
      [_, capture] -> extractor.(capture)
      _ -> nil
    end
  end

  @spec extract_timestamp(String.t()) :: String.t() | nil
  def extract_timestamp(weather_data) do
    extract_regex_value(~r/^(\d{6}[hz\/])/, weather_data)
  end

  @spec remove_timestamp(String.t()) :: String.t()
  def remove_timestamp(weather_data) do
    case Regex.run(~r/^\d{6}[hz\/]/, weather_data) do
      [timestamp] -> String.replace(weather_data, timestamp, "")
      _ -> weather_data
    end
  end

  @spec parse_wind_direction(String.t()) :: integer() | nil
  def parse_wind_direction(weather_data) do
    extract_regex_value(~r/(\d{3})\//, weather_data, &String.to_integer/1)
  end

  @spec parse_wind_speed(String.t()) :: integer() | nil
  def parse_wind_speed(weather_data) do
    extract_regex_value(~r/\/(\d{3})/, weather_data, &String.to_integer/1)
  end

  @spec parse_wind_gust(String.t()) :: integer() | nil
  def parse_wind_gust(weather_data) do
    extract_regex_value(~r/g(\d{3})/, weather_data, &String.to_integer/1)
  end

  @spec parse_temperature(String.t()) :: integer() | nil
  def parse_temperature(weather_data) do
    extract_regex_value(~r/t(-?\d{3})/, weather_data, &String.to_integer/1)
  end

  @spec parse_rainfall_1h(String.t()) :: float() | nil
  def parse_rainfall_1h(weather_data) do
    extract_regex_value(~r/r(\d{3})/, weather_data, &(String.to_integer(&1) / 100.0))
  end

  @spec parse_rainfall_24h(String.t()) :: float() | nil
  def parse_rainfall_24h(weather_data) do
    extract_regex_value(~r/p(\d{3})/, weather_data, &(String.to_integer(&1) / 100.0))
  end

  @spec parse_rainfall_since_midnight(String.t()) :: float() | nil
  def parse_rainfall_since_midnight(weather_data) do
    extract_regex_value(~r/P(\d{3})/, weather_data, &(String.to_integer(&1) / 100.0))
  end

  @spec parse_humidity(String.t()) :: integer() | nil
  def parse_humidity(weather_data) do
    extract_regex_value(~r/h(\d{2})/, weather_data, fn h ->
      h |> String.to_integer() |> normalize_humidity()
    end)
  end

  defp normalize_humidity(0), do: 100
  defp normalize_humidity(val), do: val

  @spec parse_pressure(String.t()) :: float() | nil
  def parse_pressure(weather_data) do
    extract_regex_value(~r/b(\d{5})/, weather_data, &(String.to_integer(&1) / 10.0))
  end

  @spec parse_luminosity(String.t()) :: integer() | nil
  def parse_luminosity(weather_data) do
    extract_regex_value(~r/[lL](\d{3})/, weather_data, &String.to_integer/1)
  end

  @spec parse_snow(String.t()) :: float() | nil
  def parse_snow(weather_data) do
    extract_regex_value(~r/s(\d{3})/, weather_data, &(String.to_integer(&1) / 10.0))
  end
end
