defmodule Aprs.WeatherLeadingWindTest do
  use ExUnit.Case, async: true

  alias Aprs.WeatherHelpers

  describe "slash separated leading wind" do
    test "a direction with no speed reports only the direction" do
      {weather, _rest} = WeatherHelpers.scan_weather_data("180/...g005t077")

      assert weather.wind_direction == 180
      assert weather.wind_speed == nil
      assert weather.wind_gust == 5
    end

    test "a speed with no direction reports only the speed" do
      {weather, _rest} = WeatherHelpers.scan_weather_data(".../010g005t077")

      assert weather.wind_direction == nil
      assert weather.wind_speed == 10
      assert weather.wind_gust == 5
    end

    test "a direction and speed are both reported" do
      {weather, _rest} = WeatherHelpers.scan_weather_data("180/010g005t077")

      assert weather.wind_direction == 180
      assert weather.wind_speed == 10
    end

    test "a leading weather symbol byte is skipped" do
      {weather, _rest} = WeatherHelpers.scan_weather_data("_180/...g005t077")

      assert weather.wind_direction == 180
      assert weather.wind_speed == nil
    end
  end

  describe "positionless leading wind" do
    test "a missing direction still reports the speed that follows it" do
      {weather, _rest} = WeatherHelpers.scan_weather_data("c...s010g005t077")

      assert weather.wind_direction == nil
      assert weather.wind_speed == 10
      assert weather.temperature == 77
    end

    test "a missing speed leaves the direction alone" do
      {weather, _rest} = WeatherHelpers.scan_weather_data("c220s...g005t077")

      assert weather.wind_direction == 220
      assert weather.wind_speed == nil
    end

    test "a direction with no speed field at all is still a direction" do
      {weather, _rest} = WeatherHelpers.scan_weather_data("c220g005t077")

      assert weather.wind_direction == 220
      assert weather.wind_speed == nil
      assert weather.wind_gust == 5
    end

    test "a slash separated speed after the direction is accepted" do
      {weather, _rest} = WeatherHelpers.scan_weather_data("c220/004g005t077")

      assert weather.wind_direction == 220
      assert weather.wind_speed == 4
    end
  end

  describe "positionless weather packets" do
    test "a report with no wind speed parses as weather" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:_10090556c220s...g005t077r000p000P000h50b09900")

      assert packet.data_type == :weather
      assert packet.weather.wind_direction == 220
      assert packet.weather.wind_speed == nil
      assert packet.weather.temperature == 77
    end
  end
end
