defmodule Aprs.WeatherTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Weather

  describe "parse/1" do
    test "returns a map with :data_type => :weather for valid input" do
      result = Weather.parse("_12345678c000s000g000t000r000p000P000h00b00000")
      assert is_map(result)
      assert result[:data_type] == :weather
    end

    property "always returns a map with :data_type == :weather for any string" do
      check all s <- StreamData.string(:ascii, min_length: 1, max_length: 30) do
        result = Weather.parse(s)
        assert is_map(result)
        assert result[:data_type] == :weather
      end
    end
  end

  describe "parse_from_comment/1" do
    test "parses weather data from comment with wind direction/speed" do
      comment = "175/002g003t085r000p000P000h74b10219L364AmbientCWOP.com"
      result = Weather.parse_from_comment(comment)

      assert is_map(result)
      assert result[:data_type] == :weather
      assert result[:comment] == comment
      assert result[:wind_direction] == 175
      assert result[:wind_speed] == 2
      assert result[:wind_gust] == 3
      assert result[:temperature] == 85
      assert result[:rain_1h] == 0
      assert result[:rain_24h] == 0
      assert result[:rain_since_midnight] == 0
      assert result[:humidity] == 74
      assert result[:pressure] == 1021.9
    end

    test "parses weather data from comment with temperature and humidity" do
      comment = "t072h45b10132"
      result = Weather.parse_from_comment(comment)

      assert is_map(result)
      assert result[:data_type] == :weather
      assert result[:comment] == comment
      assert result[:temperature] == 72
      assert result[:humidity] == 45
      assert result[:pressure] == 1013.2
    end

    test "returns nil for comment without weather data" do
      comment = "Just a regular comment"
      result = Weather.parse_from_comment(comment)

      assert result == nil
    end

    test "returns nil for non-string input" do
      assert Weather.parse_from_comment(nil) == nil
      assert Weather.parse_from_comment(123) == nil
      assert Weather.parse_from_comment(%{}) == nil
    end
  end

  describe "weather_packet_comment?/1" do
    test "returns true for comments with wind direction/speed" do
      assert Weather.weather_packet_comment?("175/002")
      assert Weather.weather_packet_comment?("Some text 180/015 more text")
    end

    test "returns true for comments with temperature" do
      assert Weather.weather_packet_comment?("t072")
      assert Weather.weather_packet_comment?("Temp: t085 degrees")
    end

    test "returns true for comments with humidity" do
      assert Weather.weather_packet_comment?("h45")
      assert Weather.weather_packet_comment?("Humidity: h67%")
    end

    test "returns true for comments with pressure" do
      assert Weather.weather_packet_comment?("b10132")
      assert Weather.weather_packet_comment?("Pressure: b10219 hPa")
    end

    test "returns true for comments with rain data" do
      assert Weather.weather_packet_comment?("r000")
      assert Weather.weather_packet_comment?("p123")
      assert Weather.weather_packet_comment?("P456")
    end

    test "returns true for comments with wind gust" do
      assert Weather.weather_packet_comment?("g015")
      assert Weather.weather_packet_comment?("Gusts: g025 mph")
    end

    test "returns true for complex weather comments" do
      assert Weather.weather_packet_comment?("175/002g003t085r000p000P000h74b10219L364AmbientCWOP.com")
      assert Weather.weather_packet_comment?("Wind: 180/010 Temp: t072 Humidity: h45")
    end

    test "returns false for regular comments" do
      refute Weather.weather_packet_comment?("Just a regular comment")
      refute Weather.weather_packet_comment?("Temperature is 72 degrees")
      refute Weather.weather_packet_comment?("Wind speed 10 mph")
    end

    test "returns false for non-string input" do
      refute Weather.weather_packet_comment?(nil)
      refute Weather.weather_packet_comment?(123)
      refute Weather.weather_packet_comment?(%{})
    end
  end

  describe "parse_weather_data/1" do
    test "parses complete weather data string" do
      weather_string = "175/002g003t085r000p000P000h74b10219L364"
      result = Weather.parse_weather_data(weather_string)

      assert is_map(result)
      assert result[:data_type] == :weather
      assert result[:raw_weather_data] == weather_string
      assert result[:wind_direction] == 175
      assert result[:wind_speed] == 2
      assert result[:wind_gust] == 3
      assert result[:temperature] == 85
      assert result[:rain_1h] == 0
      assert result[:rain_24h] == 0
      assert result[:rain_since_midnight] == 0
      assert result[:humidity] == 74
      assert result[:pressure] == 1021.9
      assert result[:luminosity] == 364
    end

    test "handles partial weather data" do
      weather_string = "t072h45"
      result = Weather.parse_weather_data(weather_string)

      assert is_map(result)
      assert result[:data_type] == :weather
      assert result[:temperature] == 72
      assert result[:humidity] == 45
      # Other fields should be nil
      assert result[:wind_direction] == nil
      assert result[:wind_speed] == nil
    end
  end
end
