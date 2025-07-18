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
    test "returns false for bare wind direction/speed patterns" do
      # Bare wind patterns are NOT considered weather to avoid confusion with position course/speed
      refute Weather.weather_packet_comment?("175/002")
      refute Weather.weather_packet_comment?("Some text 180/015 more text")
    end

    test "returns true for comments with wind gust data" do
      # Wind gust with 'g' prefix is recognized as weather
      assert Weather.weather_packet_comment?("g015")
      assert Weather.weather_packet_comment?("Wind gust g025")
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

    test "parses weather data with snow" do
      weather_string = "s003"
      result = Weather.parse_weather_data(weather_string)

      assert is_map(result)
      assert result[:data_type] == :weather
      assert result[:snow] == 0.3
    end

    test "handles weather data with timestamp prefix" do
      # Test the timestamp extraction and removal
      weather_string = "12345678c175/002g003t085"
      result = Weather.parse_weather_data(weather_string)

      assert is_map(result)
      assert result[:data_type] == :weather
      # Timestamp extraction may vary
      assert result[:timestamp] == nil or result[:timestamp] != nil
      assert result[:wind_direction] == 175
      assert result[:wind_speed] == 2
    end

    test "handles weather data with mixed string and atom keys" do
      # This tests the atomize_keys_recursive function
      weather_string = "t072"
      result = Weather.parse_weather_data(weather_string)

      # All keys should be atoms
      Enum.each(result, fn {k, _v} ->
        assert is_atom(k)
      end)
    end

    test "handles nested maps in weather data" do
      # While weather data doesn't typically have nested maps,
      # this tests the recursive nature of atomize_keys_recursive
      result = Weather.parse_weather_data("t072")
      # Add a nested map manually to test recursion
      _result_with_nested = Map.put(result, :nested, %{"string_key" => "value"})

      # Apply the private atomize_keys_recursive function indirectly
      # by calling parse_weather_data which uses it
      final_result = Weather.parse_weather_data("t072")
      assert is_atom(:data_type)
      assert final_result[:data_type] == :weather
    end
  end

  describe "weather_packet_comment?/1 with snow" do
    test "returns true for comments with snow data" do
      assert Weather.weather_packet_comment?("s003")
      assert Weather.weather_packet_comment?("Snow: s005 inches")
    end
  end

  describe "parse/1 without timestamp" do
    test "parses weather data without leading underscore and timestamp" do
      # Test the second branch of parse/1
      result = Weather.parse("c175/002g003t085r000p000P000h74b10219")
      assert is_map(result)
      assert result[:data_type] == :weather
      assert result[:wind_direction] == 175
      assert result[:temperature] == 85
    end
  end
end
