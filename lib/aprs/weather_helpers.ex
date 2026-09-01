defmodule Aprs.WeatherHelpers do
  @moduledoc """
  Binary weather field scanning helpers for APRS.
  """

  import Aprs.Guards

  @type weather_value :: integer() | float() | nil
  @type weather_values :: %{required(atom()) => weather_value()}

  @spec extract_timestamp_and_data(binary()) :: {String.t() | nil, binary()}
  def extract_timestamp_and_data(<<d1, d2, d3, d4, d5, d6, d7, d8, ?c, _rest::binary>> = data)
      when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) and is_digit(d6) and
             is_digit(d7) and is_digit(d8) do
    timestamp = binary_part(data, 0, 8)
    weather_data = binary_part(data, 8, byte_size(data) - 8)
    {timestamp, weather_data}
  end

  def extract_timestamp_and_data(data) when is_binary(data) do
    extract_legacy_timestamp(data, data, 0)
  end

  @spec extract_timestamp(binary()) :: String.t() | nil
  def extract_timestamp(data) do
    {timestamp, _weather_data} = extract_timestamp_and_data(data)
    timestamp
  end

  @spec remove_timestamp(binary()) :: binary()
  def remove_timestamp(data) do
    {_timestamp, weather_data} = extract_timestamp_and_data(data)
    weather_data
  end

  @spec scan_weather_data(binary()) :: {weather_values(), binary()}
  def scan_weather_data(data) when is_binary(data) do
    {rest, weather} = scan_leading_wind(data, empty_weather_values())
    scan_tokens(rest, weather)
  end

  @spec parse_wind_direction(binary()) :: integer() | nil
  def parse_wind_direction(data), do: weather_value(data, :wind_direction)

  @spec parse_wind_speed(binary()) :: integer() | nil
  def parse_wind_speed(data), do: weather_value(data, :wind_speed)

  @spec parse_wind_gust(binary()) :: integer() | nil
  def parse_wind_gust(data), do: weather_value(data, :wind_gust)

  @spec parse_temperature(binary()) :: integer() | nil
  def parse_temperature(data), do: weather_value(data, :temperature)

  @spec parse_rainfall_1h(binary()) :: float() | nil
  def parse_rainfall_1h(data), do: weather_value(data, :rain_1h)

  @spec parse_rainfall_24h(binary()) :: float() | nil
  def parse_rainfall_24h(data), do: weather_value(data, :rain_24h)

  @spec parse_rainfall_since_midnight(binary()) :: float() | nil
  def parse_rainfall_since_midnight(data), do: weather_value(data, :rain_since_midnight)

  @spec parse_humidity(binary()) :: integer() | nil
  def parse_humidity(data), do: weather_value(data, :humidity)

  @spec parse_pressure(binary()) :: float() | nil
  def parse_pressure(data), do: weather_value(data, :pressure)

  @spec parse_luminosity(binary()) :: integer() | nil
  def parse_luminosity(data), do: weather_value(data, :luminosity)

  @spec parse_snow(binary()) :: float() | nil
  def parse_snow(data), do: weather_value(data, :snow)

  @spec extract_legacy_timestamp(binary(), binary(), non_neg_integer()) :: {String.t() | nil, binary()}
  defp extract_legacy_timestamp(<<d1, d2, d3, d4, d5, d6, marker, _rest::binary>> = current, original, offset)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) and is_digit(d6) and
              marker in [?h, ?z, ?/] do
    timestamp = binary_part(current, 0, 7)
    {timestamp, remove_binary_part(original, offset, 7)}
  end

  defp extract_legacy_timestamp(<<_byte, rest::binary>>, original, offset) do
    extract_legacy_timestamp(rest, original, offset + 1)
  end

  defp extract_legacy_timestamp(<<>>, original, _offset), do: {nil, original}

  @spec remove_binary_part(binary(), non_neg_integer(), pos_integer()) :: binary()
  defp remove_binary_part(data, 0, length) do
    binary_part(data, length, byte_size(data) - length)
  end

  defp remove_binary_part(data, offset, length) do
    prefix = binary_part(data, 0, offset)
    suffix_offset = offset + length
    suffix = binary_part(data, suffix_offset, byte_size(data) - suffix_offset)
    prefix <> suffix
  end

  @spec empty_weather_values() :: weather_values()
  defp empty_weather_values do
    %{
      wind_direction: nil,
      wind_speed: nil,
      wind_gust: nil,
      temperature: nil,
      rain_1h: nil,
      rain_24h: nil,
      rain_since_midnight: nil,
      humidity: nil,
      pressure: nil,
      luminosity: nil,
      snow: nil
    }
  end

  @spec scan_leading_wind(binary(), weather_values()) :: {binary(), weather_values()}
  defp scan_leading_wind(<<?_, rest::binary>> = data, weather) do
    case consume_leading_wind(rest, weather) do
      {:ok, rest, weather} -> {rest, weather}
      :error -> {data, weather}
    end
  end

  defp scan_leading_wind(data, weather) do
    case consume_leading_wind(data, weather) do
      {:ok, rest, weather} -> {rest, weather}
      :error -> {data, weather}
    end
  end

  @spec consume_leading_wind(binary(), weather_values()) ::
          {:ok, binary(), weather_values()} | :error
  defp consume_leading_wind(<<d1, d2, d3, ?/, s1, s2, s3, rest::binary>>, weather)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(s1) and is_digit(s2) and is_digit(s3) do
    weather = %{
      weather
      | wind_direction: normalize_wind_direction(three_digits(d1, d2, d3)),
        wind_speed: three_digits(s1, s2, s3)
    }

    {:ok, rest, weather}
  end

  defp consume_leading_wind(<<d1, d2, d3, ?/, ?., ?., ?., rest::binary>>, weather)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    weather = %{weather | wind_direction: normalize_wind_direction(three_digits(d1, d2, d3))}
    {:ok, rest, weather}
  end

  defp consume_leading_wind(<<?., ?., ?., ?/, s1, s2, s3, rest::binary>>, weather)
       when is_digit(s1) and is_digit(s2) and is_digit(s3) do
    weather = %{weather | wind_speed: three_digits(s1, s2, s3)}
    {:ok, rest, weather}
  end

  defp consume_leading_wind(<<?., ?., ?., ?/, ?., ?., ?., rest::binary>>, weather) do
    {:ok, rest, weather}
  end

  defp consume_leading_wind(<<?c, d1, d2, d3, rest::binary>>, weather)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    weather = %{weather | wind_direction: normalize_wind_direction(three_digits(d1, d2, d3))}
    {rest, weather} = consume_positionless_speed(rest, weather)
    {:ok, rest, weather}
  end

  defp consume_leading_wind(<<?c, ?., ?., ?., rest::binary>>, weather) do
    {rest, weather} = consume_positionless_speed(rest, weather)
    {:ok, rest, weather}
  end

  defp consume_leading_wind(_data, _weather), do: :error

  @spec consume_positionless_speed(binary(), weather_values()) :: {binary(), weather_values()}
  defp consume_positionless_speed(<<?s, s1, s2, s3, rest::binary>>, weather)
       when is_digit(s1) and is_digit(s2) and is_digit(s3) do
    {rest, %{weather | wind_speed: three_digits(s1, s2, s3)}}
  end

  # Some stations mix the two forms and send `cNNN/NNN`.
  defp consume_positionless_speed(<<?/, s1, s2, s3, rest::binary>>, weather)
       when is_digit(s1) and is_digit(s2) and is_digit(s3) do
    {rest, %{weather | wind_speed: three_digits(s1, s2, s3)}}
  end

  defp consume_positionless_speed(<<?s, ?., ?., ?., rest::binary>>, weather), do: {rest, weather}
  defp consume_positionless_speed(data, weather), do: {data, weather}

  @spec scan_tokens(binary(), weather_values()) :: {weather_values(), binary()}
  defp scan_tokens(<<?g, d1, d2, d3, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    scan_tokens(rest, %{weather | wind_gust: three_digits(d1, d2, d3)})
  end

  defp scan_tokens(<<?g, ?., ?., ?., rest::binary>>, weather), do: scan_tokens(rest, weather)

  defp scan_tokens(<<?t, ?-, digit, rest::binary>>, weather) when is_digit(digit) do
    {temperature, rest} = consume_digits(rest, digit - ?0)
    scan_tokens(rest, %{weather | temperature: validate_temperature(-temperature)})
  end

  defp scan_tokens(<<?t, d1, d2, d3, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    temperature = d1 |> three_digits(d2, d3) |> validate_temperature()
    scan_tokens(rest, %{weather | temperature: temperature})
  end

  defp scan_tokens(<<?t, ?., ?., ?., rest::binary>>, weather), do: scan_tokens(rest, weather)

  defp scan_tokens(<<?r, d1, d2, d3, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    scan_tokens(rest, %{weather | rain_1h: three_digits(d1, d2, d3) / 100.0})
  end

  defp scan_tokens(<<?r, ?., ?., ?., rest::binary>>, weather), do: scan_tokens(rest, weather)

  defp scan_tokens(<<?p, d1, d2, d3, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    scan_tokens(rest, %{weather | rain_24h: three_digits(d1, d2, d3) / 100.0})
  end

  defp scan_tokens(<<?p, ?., ?., ?., rest::binary>>, weather), do: scan_tokens(rest, weather)

  defp scan_tokens(<<?P, d1, d2, d3, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    scan_tokens(rest, %{weather | rain_since_midnight: three_digits(d1, d2, d3) / 100.0})
  end

  defp scan_tokens(<<?P, ?., ?., ?., rest::binary>>, weather), do: scan_tokens(rest, weather)

  defp scan_tokens(<<?h, d1, d2, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) do
    humidity = d1 |> two_digits(d2) |> normalize_humidity()
    scan_tokens(rest, %{weather | humidity: humidity})
  end

  defp scan_tokens(<<?h, ?., ?., rest::binary>>, weather), do: scan_tokens(rest, weather)

  defp scan_tokens(<<?b, d1, d2, d3, d4, d5, rest::binary>>, weather)
       when is_digit(d1) and is_digit(d2) and is_digit(d3) and is_digit(d4) and is_digit(d5) do
    pressure = five_digits(d1, d2, d3, d4, d5) / 10.0
    scan_tokens(rest, %{weather | pressure: pressure})
  end

  defp scan_tokens(<<?b, ?., ?., ?., ?., ?., rest::binary>>, weather), do: scan_tokens(rest, weather)

  defp scan_tokens(<<?L, d1, d2, d3, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    scan_tokens(rest, %{weather | luminosity: three_digits(d1, d2, d3)})
  end

  defp scan_tokens(<<?l, d1, d2, d3, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    scan_tokens(rest, %{weather | luminosity: 1000 + three_digits(d1, d2, d3)})
  end

  defp scan_tokens(<<marker, ?., ?., ?., rest::binary>>, weather) when marker in [?L, ?l] do
    scan_tokens(rest, weather)
  end

  defp scan_tokens(<<?s, d1, d2, d3, rest::binary>>, weather) when is_digit(d1) and is_digit(d2) and is_digit(d3) do
    scan_tokens(rest, %{weather | snow: three_digits(d1, d2, d3) / 10.0})
  end

  defp scan_tokens(<<?s, ?., ?., ?., rest::binary>>, weather), do: scan_tokens(rest, weather)

  defp scan_tokens(<<?#, digit, rest::binary>>, weather) when is_digit(digit) do
    {_counter, rest} = consume_digits(rest, digit - ?0)
    scan_tokens(rest, weather)
  end

  defp scan_tokens(<<?v, sign, digit, rest::binary>>, weather) when sign in [?+, ?-] and is_digit(digit) do
    {_voltage, rest} = consume_digits(rest, digit - ?0)
    scan_tokens(rest, weather)
  end

  defp scan_tokens(<<?v, digit, rest::binary>>, weather) when is_digit(digit) do
    {_voltage, rest} = consume_digits(rest, digit - ?0)
    scan_tokens(rest, weather)
  end

  defp scan_tokens(data, weather), do: {weather, data}

  @spec consume_digits(binary(), non_neg_integer()) :: {non_neg_integer(), binary()}
  defp consume_digits(<<digit, rest::binary>>, value) when is_digit(digit) do
    consume_digits(rest, value * 10 + digit - ?0)
  end

  defp consume_digits(rest, value), do: {value, rest}

  @spec weather_value(binary(), atom()) :: weather_value()
  defp weather_value(data, key) do
    {weather, _remainder} = scan_weather_data(data)
    Map.fetch!(weather, key)
  end

  @spec normalize_wind_direction(non_neg_integer()) :: non_neg_integer()
  defp normalize_wind_direction(direction) when direction < 360, do: direction
  defp normalize_wind_direction(360), do: 0
  defp normalize_wind_direction(_direction), do: 0

  @spec validate_temperature(integer()) :: integer() | nil
  defp validate_temperature(temperature) when temperature >= -100 and temperature <= 150, do: temperature

  defp validate_temperature(_temperature), do: nil

  @spec normalize_humidity(non_neg_integer()) :: pos_integer()
  defp normalize_humidity(0), do: 100
  defp normalize_humidity(humidity), do: humidity

  @spec two_digits(byte(), byte()) :: non_neg_integer()
  defp two_digits(d1, d2), do: (d1 - ?0) * 10 + d2 - ?0

  @spec three_digits(byte(), byte(), byte()) :: non_neg_integer()
  defp three_digits(d1, d2, d3), do: (d1 - ?0) * 100 + (d2 - ?0) * 10 + d3 - ?0

  @spec five_digits(byte(), byte(), byte(), byte(), byte()) :: non_neg_integer()
  defp five_digits(d1, d2, d3, d4, d5) do
    (d1 - ?0) * 10_000 + (d2 - ?0) * 1000 + (d3 - ?0) * 100 + (d4 - ?0) * 10 + d5 - ?0
  end
end
