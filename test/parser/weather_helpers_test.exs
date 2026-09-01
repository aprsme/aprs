defmodule Aprs.WeatherHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.WeatherHelpers

  describe "extract_timestamp_and_data/1" do
    test "extracts an eight-digit MDHM timestamp only at the start and leaves the c marker" do
      assert WeatherHelpers.extract_timestamp_and_data("10090556c220s004") ==
               {"10090556", "c220s004"}

      assert WeatherHelpers.extract_timestamp_and_data("x10090556c220s004") ==
               {nil, "x10090556c220s004"}
    end

    test "falls back to six digits followed by h, z, or slash" do
      assert WeatherHelpers.extract_timestamp_and_data("prefix123456z090/001") ==
               {"123456z", "prefix090/001"}

      assert WeatherHelpers.extract_timestamp_and_data("123456h090/001") ==
               {"123456h", "090/001"}

      assert WeatherHelpers.extract_timestamp_and_data("123456/090/001") ==
               {"123456/", "090/001"}
    end

    test "does not treat c as a fallback six-digit timestamp marker" do
      assert WeatherHelpers.extract_timestamp_and_data("x123456c220s004") ==
               {nil, "x123456c220s004"}
    end

    property "extracts and removes a six-digit timestamp" do
      check all digits <- integer(0..999_999),
                marker <- member_of(["h", "z", "/"]),
                prefix_bytes <- list_of(member_of(?A..?F), max_length: 8),
                suffix_bytes <- list_of(member_of(?A..?F), max_length: 8) do
        prefix = List.to_string(prefix_bytes)
        suffix = List.to_string(suffix_bytes)
        timestamp = String.pad_leading(Integer.to_string(digits), 6, "0") <> marker

        assert WeatherHelpers.extract_timestamp_and_data(prefix <> timestamp <> suffix) ==
                 {timestamp, prefix <> suffix}
      end
    end
  end

  describe "scan_weather_data/1" do
    test "consumes slash-form wind and all standard tokens in one walk" do
      {weather, remainder} =
        WeatherHelpers.scan_weather_data("_123/045g015t090r001p002P003h00b10161L400s025#123v12 comment")

      assert weather == %{
               wind_direction: 123,
               wind_speed: 45,
               wind_gust: 15,
               temperature: 90,
               rain_1h: 0.01,
               rain_24h: 0.02,
               rain_since_midnight: 0.03,
               humidity: 100,
               pressure: 1016.1,
               luminosity: 400,
               snow: 2.5
             }

      assert remainder == " comment"
    end

    test "treats the s immediately after positionless c wind as speed" do
      {weather, remainder} = WeatherHelpers.scan_weather_data("c220s004g005wRSW")

      assert weather.wind_direction == 220
      assert weather.wind_speed == 4
      assert weather.wind_gust == 5
      assert weather.snow == nil
      assert remainder == "wRSW"
    end

    test "treats s as snow when it is not part of positionless wind" do
      {weather, ""} = WeatherHelpers.scan_weather_data("s004")

      assert weather.wind_speed == nil
      assert weather.snow == 0.4
    end

    test "consumes missing-value tokens without assigning values" do
      {weather, "station"} =
        WeatherHelpers.scan_weather_data(".../...g...t...r...p...P...h..b.....L...s...station")

      assert Enum.all?(weather, fn {_key, value} -> is_nil(value) end)
    end

    test "normalises invalid directions and rejects out-of-range temperatures" do
      {weather, ""} = WeatherHelpers.scan_weather_data("999/001t151")

      assert weather.wind_direction == 0
      assert weather.temperature == nil
    end

    test "adds one thousand for lowercase luminosity" do
      {weather, ""} = WeatherHelpers.scan_weather_data("l100")

      assert weather.luminosity == 1100
    end

    test "preserves the rest of the input once the comment begins" do
      {weather, remainder} = WeatherHelpers.scan_weather_data("t072ESP8266-P123-L524")

      assert weather.temperature == 72
      assert weather.rain_since_midnight == nil
      assert weather.luminosity == nil
      assert remainder == "ESP8266-P123-L524"
    end
  end

  describe "field compatibility helpers" do
    test "read their value from the shared scanner" do
      data = "123/045g015t090r001p002P003h00b10161l400s025"

      assert WeatherHelpers.parse_wind_direction(data) == 123
      assert WeatherHelpers.parse_wind_speed(data) == 45
      assert WeatherHelpers.parse_wind_gust(data) == 15
      assert WeatherHelpers.parse_temperature(data) == 90
      assert WeatherHelpers.parse_rainfall_1h(data) == 0.01
      assert WeatherHelpers.parse_rainfall_24h(data) == 0.02
      assert WeatherHelpers.parse_rainfall_since_midnight(data) == 0.03
      assert WeatherHelpers.parse_humidity(data) == 100
      assert WeatherHelpers.parse_pressure(data) == 1016.1
      assert WeatherHelpers.parse_luminosity(data) == 1400
      assert WeatherHelpers.parse_snow(data) == 2.5
    end
  end
end
