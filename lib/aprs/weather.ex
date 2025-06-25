defmodule Aprs.Weather do
  @moduledoc """
  APRS weather report parsing.
  """

  @doc """
  Parse an APRS weather report string. Returns a struct or error.
  """
  @spec parse(String.t()) :: map() | nil
  def parse("_" <> <<timestamp::binary-size(8), rest::binary>>) do
    weather_data = parse_weather_data(rest)
    Map.merge(%{timestamp: timestamp, data_type: :weather}, weather_data)
  end

  def parse(data) do
    weather_data = parse_weather_data(data)
    Map.merge(%{data_type: :weather}, weather_data)
  end

  @doc """
  Parse weather data from a comment field that contains weather information.
  This handles cases where weather data is embedded in the comment field.
  """
  @spec parse_from_comment(String.t()) :: map() | nil
  def parse_from_comment(comment) when is_binary(comment) do
    if weather_packet_comment?(comment) do
      weather_data = parse_weather_data(comment)
      Map.merge(%{data_type: :weather, comment: comment}, weather_data)
    end
  end

  def parse_from_comment(_), do: nil

  @doc """
  Check if a comment contains weather data patterns.
  """
  @spec weather_packet_comment?(String.t()) :: boolean()
  def weather_packet_comment?(comment) when is_binary(comment) do
    # Look for common weather data patterns in comments
    weather_patterns = [
      # Wind direction/speed
      ~r/\d{3}\/\d{3}/,
      # Temperature
      ~r/t\d{3}/,
      # Humidity
      ~r/h\d{2}/,
      # Pressure
      ~r/b\d{5}/,
      # Rain
      ~r/r\d{3}/,
      # Wind gust
      ~r/g\d{3}/,
      # Rain 24h
      ~r/p\d{3}/,
      # Rain since midnight
      ~r/P\d{3}/
    ]

    Enum.any?(weather_patterns, &Regex.match?(&1, comment))
  end

  def weather_packet_comment?(_), do: false

  @doc """
  Parses a weather data string into a map of weather values.
  """
  @spec parse_weather_data(String.t()) :: map()
  def parse_weather_data(weather_data) do
    timestamp = Aprs.WeatherHelpers.extract_timestamp(weather_data)
    weather_data = Aprs.WeatherHelpers.remove_timestamp(weather_data)

    weather_values = %{
      wind_direction: Aprs.WeatherHelpers.parse_wind_direction(weather_data),
      wind_speed: Aprs.WeatherHelpers.parse_wind_speed(weather_data),
      wind_gust: Aprs.WeatherHelpers.parse_wind_gust(weather_data),
      temperature: Aprs.WeatherHelpers.parse_temperature(weather_data),
      rain_1h: Aprs.WeatherHelpers.parse_rainfall_1h(weather_data),
      rain_24h: Aprs.WeatherHelpers.parse_rainfall_24h(weather_data),
      rain_since_midnight: Aprs.WeatherHelpers.parse_rainfall_since_midnight(weather_data),
      humidity: Aprs.WeatherHelpers.parse_humidity(weather_data),
      pressure: Aprs.WeatherHelpers.parse_pressure(weather_data),
      luminosity: Aprs.WeatherHelpers.parse_luminosity(weather_data),
      snow: Aprs.WeatherHelpers.parse_snow(weather_data)
    }

    # Ensure all keys are atoms in the result
    result = %{timestamp: timestamp, data_type: :weather, raw_weather_data: weather_data}

    Enum.reduce(weather_values, result, fn {key, value}, acc ->
      put_weather_value(acc, key, value)
    end)
    |> atomize_keys_recursive()
  end

  defp put_weather_value(acc, _key, nil), do: acc
  defp put_weather_value(acc, key, value), do: Map.put(acc, key, value)

  # Recursively convert all string keys in a map to atoms
  defp atomize_keys_recursive(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize_keys_recursive(v)}
      {k, v} -> {k, atomize_keys_recursive(v)}
    end)
    |> Enum.into(%{})
  end
  defp atomize_keys_recursive(other), do: other
end
