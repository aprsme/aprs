defmodule Aprs.Weather do
  @moduledoc """
  APRS weather report parsing.
  """

  import Aprs.Guards

  @typep weather_value :: integer() | float() | nil | String.t() | atom() | %{atom() => integer() | float() | nil}
  @typep weather_map :: %{atom() => weather_value}

  @doc """
  Parse an APRS weather report string. Returns a struct or error.
  """
  @spec parse(String.t()) :: map() | nil
  def parse("_" <> <<timestamp::binary-size(7), rest::binary>>) do
    weather_data = parse_weather_data(rest)
    Map.merge(weather_data, %{timestamp: timestamp, data_type: :weather})
  end

  def parse("c" <> rest) do
    # Complete weather format without timestamp
    weather_data = parse_weather_data(rest)
    Map.merge(%{data_type: :weather}, weather_data)
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
    parse_comment_with_weather_check(comment, weather_packet_comment?(comment))
  end

  def parse_from_comment(_), do: nil

  @spec parse_comment_with_weather_check(String.t(), boolean()) :: map() | nil
  defp parse_comment_with_weather_check(_comment, false), do: nil

  defp parse_comment_with_weather_check(comment, true) do
    weather_data = parse_weather_data(comment)
    Map.merge(%{comment: comment, data_type: :weather}, weather_data)
  end

  @doc """
  Check if a comment contains weather data patterns using binary pattern matching.
  """
  @spec weather_packet_comment?(String.t()) :: boolean()
  def weather_packet_comment?(comment) when is_binary(comment) do
    # Check for weather-specific patterns to avoid misidentifying position packets
    has_weather_pattern?(comment)
  end

  def weather_packet_comment?(_), do: false

  # Use binary pattern matching to check for weather patterns
  @spec has_weather_pattern?(binary()) :: boolean()
  defp has_weather_pattern?(data), do: check_weather_patterns(data)

  @spec check_weather_patterns(binary()) :: boolean()
  defp check_weather_patterns(<<>>), do: false

  # Temperature pattern (t followed by 3 digits)
  defp check_weather_patterns(<<?t, d1::8, d2::8, d3::8, _::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    true
  end

  # Temperature pattern with negative (t- followed by 3 digits)
  defp check_weather_patterns(<<?t, ?-, d1::8, d2::8, d3::8, _::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    true
  end

  # Humidity pattern (h followed by 2 digits)
  defp check_weather_patterns(<<?h, d1::8, d2::8, _::binary>>) when is_digit(d1) and is_digit(d2) do
    true
  end

  # Pressure pattern (b followed by 5 digits)
  defp check_weather_patterns(<<?b, d1::8, d2::8, d3::8, d4::8, d5::8, _::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) do
    true
  end

  # Rain 1h pattern (r followed by 3 digits)
  defp check_weather_patterns(<<?r, d1::8, d2::8, d3::8, _::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    true
  end

  # Wind gust pattern (g followed by 3 digits)
  defp check_weather_patterns(<<?g, d1::8, d2::8, d3::8, _::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    true
  end

  # Rain 24h pattern (p followed by 3 digits)
  defp check_weather_patterns(<<?p, d1::8, d2::8, d3::8, _::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    true
  end

  # Rain since midnight pattern (P followed by 3 digits)
  defp check_weather_patterns(<<?P, d1::8, d2::8, d3::8, _::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    true
  end

  # Snow pattern (s followed by 3 digits)
  defp check_weather_patterns(<<?s, d1::8, d2::8, d3::8, _::binary>>)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    true
  end

  # Luminosity pattern (l or L followed by 3 digits)
  defp check_weather_patterns(<<marker::8, d1::8, d2::8, d3::8, _::binary>>)
       when marker in [?l, ?L] and is_digit(d1) and is_digit(d2) and is_digit(d3) do
    true
  end

  # Continue scanning
  defp check_weather_patterns(<<_::8, rest::binary>>), do: check_weather_patterns(rest)

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
    result = %{timestamp: timestamp, raw_weather_data: weather_data}

    full_weather_data =
      weather_values
      |> Enum.reduce(result, fn {key, value}, acc ->
        put_weather_value(acc, key, value)
      end)
      |> atomize_keys_recursive()

    # Add wx field (contains all weather values)
    full_weather_data
    |> Map.put(:wx, weather_values)
    |> Map.put(:data_type, :weather)
  end

  # Always put the key in the map, even if the value is nil
  @spec put_weather_value(weather_map(), atom(), weather_value()) :: weather_map()
  defp put_weather_value(acc, key, value), do: Map.put(acc, key, value)

  # Recursively convert all string keys in a map to atoms
  @spec atomize_keys_recursive(weather_map() | weather_value()) :: weather_map() | weather_value()
  defp atomize_keys_recursive(map) when is_map(map) do
    Map.new(map, &atomize_key_value_pair/1)
  end

  defp atomize_keys_recursive(other), do: other

  @spec atomize_key_value_pair({atom() | String.t(), weather_map() | weather_value()}) ::
          {atom() | String.t(), weather_map() | weather_value()}
  defp atomize_key_value_pair({k, v}) do
    {k, atomize_keys_recursive(v)}
  end
end
