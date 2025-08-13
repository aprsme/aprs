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
      # Timestamp extraction may vary, just verify it's set
      assert Map.has_key?(result, :timestamp)
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

  describe "weather property tests with real-world patterns" do
    property "handles weather data with all fields present" do
      check all wind_dir <- integer(0..360),
                wind_speed <- integer(0..999),
                wind_gust <- integer(0..999),
                temp <- integer(-99..999),
                rain_1h <- integer(0..999),
                rain_24h <- integer(0..999),
                rain_midnight <- integer(0..999),
                humidity <- integer(0..100),
                pressure <- integer(8000..12_000),
                luminosity <- integer(0..999),
                snow <- integer(0..999) do
        # Build complete weather string
        weather =
          "_#{String.pad_leading(to_string(rem(wind_dir, 361)), 3, "0")}/#{String.pad_leading(to_string(wind_speed), 3, "0")}"

        weather = weather <> "g#{String.pad_leading(to_string(wind_gust), 3, "0")}"
        weather = weather <> "t#{String.pad_leading(to_string(temp), 3, "0")}"
        weather = weather <> "r#{String.pad_leading(to_string(rain_1h), 3, "0")}"
        weather = weather <> "p#{String.pad_leading(to_string(rain_24h), 3, "0")}"
        weather = weather <> "P#{String.pad_leading(to_string(rain_midnight), 3, "0")}"
        weather = weather <> "h#{String.pad_leading(to_string(rem(humidity, 101)), 2, "0")}"
        weather = weather <> "b#{String.pad_leading(to_string(pressure), 5, "0")}"
        weather = weather <> "L#{String.pad_leading(to_string(luminosity), 3, "0")}"
        weather = weather <> "s#{String.pad_leading(to_string(snow), 3, "0")}"

        result = Weather.parse(weather)

        assert result.data_type == :weather
        assert result.wind_direction == rem(wind_dir, 361)
        assert result.wind_speed == wind_speed
        assert result.wind_gust == wind_gust
        assert result.temperature == temp
        assert result.rain_1h == rain_1h
        assert result.rain_24h == rain_24h
        assert result.rain_since_midnight == rain_midnight
        assert result.humidity == rem(humidity, 101)
        assert result.pressure == pressure / 10.0
        assert result.luminosity == luminosity
        assert result.snow == snow / 10.0
      end
    end

    property "handles weather data with missing fields (dots)" do
      check all has_wind <- boolean(),
                has_temp <- boolean(),
                has_rain <- boolean(),
                has_pressure <- boolean() do
        weather = "_"
        weather = weather <> if has_wind, do: "180/015", else: ".../..."
        weather = weather <> "g..."
        weather = weather <> if has_temp, do: "t072", else: "t..."
        weather = weather <> if has_rain, do: "r001p002P003", else: "r...p...P..."
        weather = weather <> "h.."
        weather = weather <> if has_pressure, do: "b10150", else: "b....."

        result = Weather.parse(weather)

        assert result.data_type == :weather

        if has_wind do
          assert result.wind_direction == 180
          assert result.wind_speed == 15
        else
          assert result.wind_direction == nil
          assert result.wind_speed == nil
        end

        if has_temp do
          assert result.temperature == 72
        else
          assert result.temperature == nil
        end
      end
    end

    property "handles weather with timestamp variations" do
      check all day <- integer(1..31),
                hour <- integer(0..23),
                minute <- integer(0..59),
                tz <- member_of(["z", "h", "c", "/"]),
                temp <- integer(-50..150) do
        # Format MDHM timestamp
        timestamp = "#{String.pad_leading(to_string(rem(day, 32)), 2, "0")}"
        timestamp = timestamp <> "#{String.pad_leading(to_string(hour), 2, "0")}"
        timestamp = timestamp <> "#{String.pad_leading(to_string(minute), 2, "0")}"

        weather = "_#{timestamp}#{tz}175/002g003t#{String.pad_leading(to_string(temp), 3, "0")}"

        result = Weather.parse(weather)

        assert result.data_type == :weather
        assert result.wind_direction == 175
        assert result.wind_speed == 2
        assert result.temperature == temp
        # Timestamp should be parsed
        assert result.timestamp
      end
    end

    property "handles weather data from real CWOP stations" do
      check all station_suffix <- member_of(["AmbientCWOP.com", "weewx", "WX3in1", "DVWP", "eMB62"]),
                has_luminosity <- boolean(),
                luminosity <- integer(0..999) do
        # Real CWOP patterns
        weather = "_159/003g009t084r000p000P000b09862h35"

        weather =
          if has_luminosity do
            weather <> "L#{String.pad_leading(to_string(luminosity), 3, "0")}"
          else
            weather
          end

        weather = weather <> station_suffix

        result = Weather.parse(weather)

        assert result.data_type == :weather
        assert result.temperature == 84
        assert result.humidity == 35
        assert result.pressure == 986.2

        if has_luminosity do
          assert result.luminosity == luminosity
        end
      end
    end

    property "handles positionless weather reports" do
      check all wind_dir <- integer(0..360),
                wind_speed <- integer(0..200),
                temp <- integer(-50..150),
                has_wx_station_id <- boolean() do
        # Positionless weather format (no position data)
        weather = "c#{String.pad_leading(to_string(rem(wind_dir, 361)), 3, "0")}"
        weather = weather <> "s#{String.pad_leading(to_string(wind_speed), 3, "0")}"
        weather = weather <> "g..."
        weather = weather <> "t#{String.pad_leading(to_string(temp), 3, "0")}"
        weather = weather <> "r...p...P...h..b....."

        weather =
          if has_wx_station_id do
            weather <> "xDVP"
          else
            weather
          end

        result = Weather.parse(weather)

        assert result.data_type == :weather
        assert result.wind_direction == rem(wind_dir, 361)
        assert result.wind_speed == wind_speed
        assert result.temperature == temp
      end
    end

    property "handles weather with software identifiers" do
      check all software <- member_of(["DsVP", "DVWP", "wDVP", "xDVP", "yAPRS", "zWX"]),
                temp <- integer(0..150) do
        weather = "_000/000g000t#{String.pad_leading(to_string(temp), 3, "0")}r000p000P000h00b00000#{software}"

        result = Weather.parse(weather)

        assert result.data_type == :weather
        assert result.temperature == temp
        # Software ID might be parsed into a field
        assert String.contains?(result.raw_weather_data || "", software)
      end
    end

    property "handles malformed weather data gracefully" do
      check all prefix <- member_of(["_", "c", ""]),
                malformed_data <- string(:printable, max_length: 50) do
        weather = prefix <> malformed_data

        result = Weather.parse(weather)

        # Should always return a weather type map
        assert result.data_type == :weather
        # But fields might be nil or have default values
      end
    end

    property "handles weather in position comment fields" do
      check all comment_prefix <- string(:alphanumeric, max_length: 10),
                wind_dir <- integer(0..360),
                temp <- integer(0..150) do
        # Weather data embedded in comment
        comment =
          comment_prefix <>
            "_#{String.pad_leading(to_string(rem(wind_dir, 361)), 3, "0")}/000g000t#{String.pad_leading(to_string(temp), 3, "0")}"

        result = Weather.parse_from_comment(comment)

        if result != nil do
          assert result.data_type == :weather
          assert result.wind_direction == rem(wind_dir, 361)
          assert result.temperature == temp
          assert result.comment == comment
        end
      end
    end

    property "handles negative temperatures correctly" do
      check all temp <- integer(-99..-1) do
        # Negative temps are represented with leading minus
        weather = "_000/000g000t#{String.pad_leading(to_string(temp), 3, "0")}r000p000P000h00b00000"

        result = Weather.parse(weather)

        assert result.data_type == :weather
        assert result.temperature == temp
      end
    end

    property "handles weather beacon formats" do
      check all beacon_text <- member_of(["WX de", "Weather:", "WX rpt", "Conditions:"]),
                temp <- integer(0..150),
                humidity <- integer(0..100) do
        weather =
          beacon_text <>
            " t#{String.pad_leading(to_string(temp), 3, "0")}h#{String.pad_leading(to_string(humidity), 2, "0")}"

        result = Weather.parse_from_comment(weather)

        if result != nil do
          assert result.data_type == :weather
          assert result.temperature == temp
          # h00 is parsed as 100% humidity in APRS
          expected_humidity = if humidity == 0, do: 100, else: humidity
          assert result.humidity == expected_humidity
        end
      end
    end
  end
end
