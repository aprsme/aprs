defmodule Aprs.WeatherTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Weather

  @weather_keys [
    :humidity,
    :luminosity,
    :pressure,
    :rain_1h,
    :rain_24h,
    :rain_since_midnight,
    :raw_weather_data,
    :snow,
    :temperature,
    :timestamp,
    :wind_direction,
    :wind_gust,
    :wind_speed
  ]

  describe "parse/1" do
    test "parses the APRS positionless weather example" do
      result = Weather.parse("10090556c220s004g005t077r000p000P000h50b09900wRSW")

      assert result.data_type == :weather
      assert result.timestamp == "10090556"
      assert result.wind_direction == 220
      assert result.wind_speed == 4
      assert result.wind_gust == 5
      assert result.temperature == 77
      assert result.rain_1h == 0.0
      assert result.rain_24h == 0.0
      assert result.rain_since_midnight == 0.0
      assert result.humidity == 50
      assert result.pressure == 990.0
      assert result.snow == nil
      assert result.raw_weather_data == "c220s004g005t077r000p000P000h50b09900wRSW"
    end

    test "adds the weather data type without nesting a wx copy" do
      result = Weather.parse("090/004g005t077")

      assert result.data_type == :weather
      refute Map.has_key?(result, :wx)
      assert result |> Map.delete(:data_type) |> Map.keys() |> Enum.sort() == @weather_keys
    end

    property "always returns a weather map for a binary" do
      check all data <- StreamData.string(:ascii, max_length: 40) do
        assert %{data_type: :weather} = Weather.parse(data)
      end
    end
  end

  describe "parse_weather_data/1" do
    test "returns one flat map with every weather key present" do
      weather = "175/002g003t085r000p000P000h74b10219L364s003"
      result = Weather.parse_weather_data(weather)

      assert result |> Map.keys() |> Enum.sort() == @weather_keys
      assert result.raw_weather_data == weather
      assert result.timestamp == nil
      assert result.wind_direction == 175
      assert result.wind_speed == 2
      assert result.wind_gust == 3
      assert result.temperature == 85
      assert result.rain_1h == 0.0
      assert result.rain_24h == 0.0
      assert result.rain_since_midnight == 0.0
      assert result.humidity == 74
      assert result.pressure == 1021.9
      assert result.luminosity == 364
      assert result.snow == 0.3
      refute Map.has_key?(result, :data_type)
      refute Map.has_key?(result, :wx)
    end

    test "uses nil for absent and dotted fields" do
      result = Weather.parse_weather_data(".../...g...t...r...p...P...h..b.....L...s...")

      assert result.wind_direction == nil
      assert result.wind_speed == nil
      assert result.wind_gust == nil
      assert result.temperature == nil
      assert result.rain_1h == nil
      assert result.rain_24h == nil
      assert result.rain_since_midnight == nil
      assert result.humidity == nil
      assert result.pressure == nil
      assert result.luminosity == nil
      assert result.snow == nil
    end

    test "normalises wind direction and validates temperature" do
      assert Weather.parse_weather_data("360/001t150").wind_direction == 0
      assert Weather.parse_weather_data("999/001t151").wind_direction == 0
      assert Weather.parse_weather_data("000/001t151").temperature == nil
      assert Weather.parse_weather_data("000/001t-100").temperature == -100
      assert Weather.parse_weather_data("000/001t-101").temperature == nil
    end

    test "normalises zero humidity to one hundred percent" do
      assert Weather.parse_weather_data("h00").humidity == 100
    end

    test "decodes upper- and lowercase luminosity markers differently" do
      assert Weather.parse_weather_data("L100").luminosity == 100
      assert Weather.parse_weather_data("l100").luminosity == 1100
    end

    property "decodes complete weather reports" do
      check all wind_direction <- integer(0..360),
                wind_speed <- integer(0..999),
                wind_gust <- integer(0..999),
                temperature <- integer(-100..150),
                rain_1h <- integer(0..999),
                rain_24h <- integer(0..999),
                rain_midnight <- integer(0..999),
                humidity <- integer(0..99),
                pressure <- integer(8000..12_000),
                luminosity <- integer(0..999),
                snow <- integer(0..999) do
        temperature_token =
          if temperature < 0 do
            "t-" <> String.pad_leading(Integer.to_string(abs(temperature)), 3, "0")
          else
            "t" <> String.pad_leading(Integer.to_string(temperature), 3, "0")
          end

        weather =
          String.pad_leading(Integer.to_string(wind_direction), 3, "0") <>
            "/" <>
            String.pad_leading(Integer.to_string(wind_speed), 3, "0") <>
            "g" <>
            String.pad_leading(Integer.to_string(wind_gust), 3, "0") <>
            temperature_token <>
            "r" <>
            String.pad_leading(Integer.to_string(rain_1h), 3, "0") <>
            "p" <>
            String.pad_leading(Integer.to_string(rain_24h), 3, "0") <>
            "P" <>
            String.pad_leading(Integer.to_string(rain_midnight), 3, "0") <>
            "h" <>
            String.pad_leading(Integer.to_string(humidity), 2, "0") <>
            "b" <>
            String.pad_leading(Integer.to_string(pressure), 5, "0") <>
            "L" <>
            String.pad_leading(Integer.to_string(luminosity), 3, "0") <>
            "s" <>
            String.pad_leading(Integer.to_string(snow), 3, "0")

        result = Weather.parse_weather_data(weather)

        assert result.wind_direction == rem(wind_direction, 360)
        assert result.wind_speed == wind_speed
        assert result.wind_gust == wind_gust
        assert result.temperature == temperature
        assert result.rain_1h == rain_1h / 100.0
        assert result.rain_24h == rain_24h / 100.0
        assert result.rain_since_midnight == rain_midnight / 100.0
        assert result.humidity == if(humidity == 0, do: 100, else: humidity)
        assert result.pressure == pressure / 10.0
        assert result.luminosity == luminosity
        assert result.snow == snow / 10.0
      end
    end
  end

  describe "parse_weather_data_with_remainder/1" do
    test "returns the unconsumed comment" do
      {weather, remainder} = Weather.parse_weather_data_with_remainder("090/000g005t077Weather station")

      assert weather.wind_direction == 90
      assert weather.wind_speed == 0
      assert weather.wind_gust == 5
      assert weather.temperature == 77
      assert remainder == "Weather station"
    end

    test "trims the remainder and consumes rain-counter and voltage extensions" do
      {weather, remainder} =
        Weather.parse_weather_data_with_remainder("090/000g005#12345v-02  Station")

      assert weather.wind_gust == 5
      assert remainder == "Station"
    end

    test "does not consume weather-looking bytes after the comment begins" do
      {_weather, remainder} =
        Weather.parse_weather_data_with_remainder("000/000g000t010r000p000P000h80b10166ESP8266-BME280")

      assert remainder == "ESP8266-BME280"
    end
  end
end
