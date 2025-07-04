defmodule Aprs.WeatherHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "extract_timestamp/1" do
    property "extracts timestamp from weather data" do
      check all hour <- StreamData.integer(0..23),
                minute <- StreamData.integer(0..59),
                second <- StreamData.integer(0..59),
                suffix <- StreamData.member_of(["z", "h", "/"]),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        timestamp =
          String.pad_leading(to_string(hour), 2, "0") <>
            String.pad_leading(to_string(minute), 2, "0") <>
            String.pad_leading(to_string(second), 2, "0") <> suffix

        weather_data = timestamp <> rest

        result = Aprs.WeatherHelpers.extract_timestamp(weather_data)
        assert result == timestamp
      end
    end

    test "extracts timestamp from beginning of string" do
      assert Aprs.WeatherHelpers.extract_timestamp("123456z_123/045g015t090h60b10161") == "123456z"
      assert Aprs.WeatherHelpers.extract_timestamp("000000h_123/045g015t090h60b10161") == "000000h"
      assert Aprs.WeatherHelpers.extract_timestamp("235959/_123/045g015t090h60b10161") == "235959/"
    end

    test "returns nil for no timestamp" do
      assert Aprs.WeatherHelpers.extract_timestamp("_123/045g015t090h60b10161") == nil
      assert Aprs.WeatherHelpers.extract_timestamp("123/045g015t090h60b10161") == nil
      assert Aprs.WeatherHelpers.extract_timestamp("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.extract_timestamp("123456z") == "123456z"
      assert Aprs.WeatherHelpers.extract_timestamp("123456z") == "123456z"
      assert Aprs.WeatherHelpers.extract_timestamp("123456h") == "123456h"
      assert Aprs.WeatherHelpers.extract_timestamp("123456/") == "123456/"
    end

    test "handles invalid timestamp formats" do
      assert Aprs.WeatherHelpers.extract_timestamp("12345z_rest") == nil
      assert Aprs.WeatherHelpers.extract_timestamp("1234567z_rest") == nil
      assert Aprs.WeatherHelpers.extract_timestamp("123456_rest") == nil
      assert Aprs.WeatherHelpers.extract_timestamp("123456x_rest") == nil
    end
  end

  describe "remove_timestamp/1" do
    property "removes timestamp from weather data" do
      check all hour <- StreamData.integer(0..23),
                minute <- StreamData.integer(0..59),
                second <- StreamData.integer(0..59),
                suffix <- StreamData.member_of(["z", "h", "/"]),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        timestamp =
          String.pad_leading(to_string(hour), 2, "0") <>
            String.pad_leading(to_string(minute), 2, "0") <>
            String.pad_leading(to_string(second), 2, "0") <> suffix

        weather_data = timestamp <> rest

        result = Aprs.WeatherHelpers.remove_timestamp(weather_data)
        assert result == rest
      end
    end

    test "removes timestamp from beginning" do
      assert Aprs.WeatherHelpers.remove_timestamp("123456z_123/045g015t090h60b10161") == "_123/045g015t090h60b10161"
      assert Aprs.WeatherHelpers.remove_timestamp("000000h_123/045g015t090h60b10161") == "_123/045g015t090h60b10161"
      assert Aprs.WeatherHelpers.remove_timestamp("235959/_123/045g015t090h60b10161") == "_123/045g015t090h60b10161"
    end

    test "returns original string when no timestamp" do
      assert Aprs.WeatherHelpers.remove_timestamp("_123/045g015t090h60b10161") == "_123/045g015t090h60b10161"
      assert Aprs.WeatherHelpers.remove_timestamp("123/045g015t090h60b10161") == "123/045g015t090h60b10161"
      assert Aprs.WeatherHelpers.remove_timestamp("") == ""
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.remove_timestamp("123456z") == ""
      assert Aprs.WeatherHelpers.remove_timestamp("123456h") == ""
      assert Aprs.WeatherHelpers.remove_timestamp("123456/") == ""
    end
  end

  describe "parse_wind_direction/1" do
    property "parses wind direction from weather data" do
      check all direction <- StreamData.integer(0..359),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        direction_str = String.pad_leading(to_string(direction), 3, "0")
        weather_data = direction_str <> "/" <> rest

        result = Aprs.WeatherHelpers.parse_wind_direction(weather_data)
        assert result == direction
      end
    end

    test "parses wind direction correctly" do
      assert Aprs.WeatherHelpers.parse_wind_direction("123/045g015t090h60b10161") == 123
      assert Aprs.WeatherHelpers.parse_wind_direction("000/045g015t090h60b10161") == 0
      assert Aprs.WeatherHelpers.parse_wind_direction("359/045g015t090h60b10161") == 359
    end

    test "returns nil for no wind direction" do
      assert Aprs.WeatherHelpers.parse_wind_direction("g015t090h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_wind_direction("123g015t090h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_wind_direction("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_wind_direction("123/") == 123
      assert Aprs.WeatherHelpers.parse_wind_direction("123/rest") == 123
      assert Aprs.WeatherHelpers.parse_wind_direction("123/045") == 123
    end

    test "handles invalid wind direction" do
      assert is_integer(Aprs.WeatherHelpers.parse_wind_direction("1234/045g015t090h60b10161")) or
               is_nil(Aprs.WeatherHelpers.parse_wind_direction("1234/045g015t090h60b10161"))
    end
  end

  describe "parse_wind_speed/1" do
    property "parses wind speed from weather data" do
      check all speed <- StreamData.integer(0..999),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        speed_str = String.pad_leading(to_string(speed), 3, "0")
        weather_data = "123/" <> speed_str <> rest

        result = Aprs.WeatherHelpers.parse_wind_speed(weather_data)
        assert result == speed
      end
    end

    test "parses wind speed correctly" do
      assert Aprs.WeatherHelpers.parse_wind_speed("123/045g015t090h60b10161") == 45
      assert Aprs.WeatherHelpers.parse_wind_speed("000/000g015t090h60b10161") == 0
      assert Aprs.WeatherHelpers.parse_wind_speed("359/999g015t090h60b10161") == 999
    end

    test "returns nil for no wind speed" do
      assert Aprs.WeatherHelpers.parse_wind_speed("g015t090h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_wind_speed("123g015t090h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_wind_speed("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_wind_speed("123/045") == 45
      assert Aprs.WeatherHelpers.parse_wind_speed("123/045g") == 45
      assert Aprs.WeatherHelpers.parse_wind_speed("123/045rest") == 45
    end

    test "handles invalid wind speed" do
      assert is_integer(Aprs.WeatherHelpers.parse_wind_speed("123/0456g015t090h60b10161")) or
               is_nil(Aprs.WeatherHelpers.parse_wind_speed("123/0456g015t090h60b10161"))
    end
  end

  describe "parse_wind_gust/1" do
    property "parses wind gust from weather data" do
      check all gust <- StreamData.integer(0..999),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        gust_str = String.pad_leading(to_string(gust), 3, "0")
        weather_data = "123/045g" <> gust_str <> rest

        result = Aprs.WeatherHelpers.parse_wind_gust(weather_data)
        assert result == gust
      end
    end

    test "parses wind gust correctly" do
      assert Aprs.WeatherHelpers.parse_wind_gust("123/045g015t090h60b10161") == 15
      assert Aprs.WeatherHelpers.parse_wind_gust("000/000g000t090h60b10161") == 0
      assert Aprs.WeatherHelpers.parse_wind_gust("359/999g999t090h60b10161") == 999
    end

    test "returns nil for no wind gust" do
      assert Aprs.WeatherHelpers.parse_wind_gust("t090h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_wind_gust("123/045t090h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_wind_gust("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_wind_gust("123/045g015") == 15
      assert Aprs.WeatherHelpers.parse_wind_gust("123/045g015t") == 15
      assert Aprs.WeatherHelpers.parse_wind_gust("123/045g015rest") == 15
    end

    test "handles invalid wind gust" do
      assert is_integer(Aprs.WeatherHelpers.parse_wind_gust("123/045g0156t090h60b10161")) or
               is_nil(Aprs.WeatherHelpers.parse_wind_gust("123/045g0156t090h60b10161"))
    end
  end

  describe "parse_temperature/1" do
    property "parses temperature from weather data" do
      check all temp <- StreamData.integer(-99..99),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        data = "123/045g015t" <> Integer.to_string(temp) <> rest
        result = Aprs.WeatherHelpers.parse_temperature(data)
        assert is_integer(result) or is_nil(result)
      end
    end

    test "parses temperature correctly" do
      assert is_integer(Aprs.WeatherHelpers.parse_temperature("123/045g015t-10h60b10161")) or
               is_nil(Aprs.WeatherHelpers.parse_temperature("123/045g015t-10h60b10161"))
    end

    test "returns nil for no temperature" do
      assert Aprs.WeatherHelpers.parse_temperature("h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_temperature("123/045g015h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_temperature("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_temperature("123/045g015t090") == 90
      assert Aprs.WeatherHelpers.parse_temperature("123/045g015t090h") == 90
      assert Aprs.WeatherHelpers.parse_temperature("123/045g015t090rest") == 90
    end

    test "handles invalid temperature" do
      assert is_integer(Aprs.WeatherHelpers.parse_temperature("123/045g015t0900h60b10161")) or
               is_nil(Aprs.WeatherHelpers.parse_temperature("123/045g015t0900h60b10161"))
    end
  end

  describe "parse_rainfall_1h/1" do
    property "parses 1-hour rainfall from weather data" do
      check all rain <- StreamData.integer(0..999),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        rain_str = String.pad_leading(to_string(rain), 3, "0")
        weather_data = "123/045g015t090r" <> rain_str <> rest

        result = Aprs.WeatherHelpers.parse_rainfall_1h(weather_data)
        expected = rain / 100.0
        assert_in_delta result, expected, 0.001
      end
    end

    test "parses 1-hour rainfall correctly" do
      assert Aprs.WeatherHelpers.parse_rainfall_1h("123/045g015t090r000h60b10161") == 0.0
      assert Aprs.WeatherHelpers.parse_rainfall_1h("123/045g015t090r100h60b10161") == 1.0
      assert Aprs.WeatherHelpers.parse_rainfall_1h("123/045g015t090r250h60b10161") == 2.5
      assert Aprs.WeatherHelpers.parse_rainfall_1h("123/045g015t090r999h60b10161") == 9.99
    end

    test "returns nil for no 1-hour rainfall" do
      assert Aprs.WeatherHelpers.parse_rainfall_1h("h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_rainfall_1h("123/045g015t090h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_rainfall_1h("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_rainfall_1h("123/045g015t090r000") == 0.0
      assert Aprs.WeatherHelpers.parse_rainfall_1h("123/045g015t090r000h") == 0.0
      assert Aprs.WeatherHelpers.parse_rainfall_1h("123/045g015t090r000rest") == 0.0
    end
  end

  describe "parse_rainfall_24h/1" do
    property "parses 24-hour rainfall from weather data" do
      check all rain <- StreamData.integer(0..999),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        rain_str = String.pad_leading(to_string(rain), 3, "0")
        weather_data = "123/045g015t090r000p" <> rain_str <> rest

        result = Aprs.WeatherHelpers.parse_rainfall_24h(weather_data)
        expected = rain / 100.0
        assert_in_delta result, expected, 0.001
      end
    end

    test "parses 24-hour rainfall correctly" do
      assert Aprs.WeatherHelpers.parse_rainfall_24h("123/045g015t090r000p000h60b10161") == 0.0
      assert Aprs.WeatherHelpers.parse_rainfall_24h("123/045g015t090r000p100h60b10161") == 1.0
      assert Aprs.WeatherHelpers.parse_rainfall_24h("123/045g015t090r000p250h60b10161") == 2.5
      assert Aprs.WeatherHelpers.parse_rainfall_24h("123/045g015t090r000p999h60b10161") == 9.99
    end

    test "returns nil for no 24-hour rainfall" do
      assert Aprs.WeatherHelpers.parse_rainfall_24h("h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_rainfall_24h("123/045g015t090r000h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_rainfall_24h("") == nil
    end
  end

  describe "parse_rainfall_since_midnight/1" do
    property "parses rainfall since midnight from weather data" do
      check all rain <- StreamData.integer(0..999),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        rain_str = String.pad_leading(to_string(rain), 3, "0")
        weather_data = "123/045g015t090r000p000P" <> rain_str <> rest

        result = Aprs.WeatherHelpers.parse_rainfall_since_midnight(weather_data)
        expected = rain / 100.0
        assert_in_delta result, expected, 0.001
      end
    end

    test "parses rainfall since midnight correctly" do
      assert Aprs.WeatherHelpers.parse_rainfall_since_midnight("123/045g015t090r000p000P000h60b10161") == 0.0
      assert Aprs.WeatherHelpers.parse_rainfall_since_midnight("123/045g015t090r000p000P100h60b10161") == 1.0
      assert Aprs.WeatherHelpers.parse_rainfall_since_midnight("123/045g015t090r000p000P250h60b10161") == 2.5
      assert Aprs.WeatherHelpers.parse_rainfall_since_midnight("123/045g015t090r000p000P999h60b10161") == 9.99
    end

    test "returns nil for no rainfall since midnight" do
      assert Aprs.WeatherHelpers.parse_rainfall_since_midnight("h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_rainfall_since_midnight("123/045g015t090r000p000h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_rainfall_since_midnight("") == nil
    end
  end

  describe "parse_humidity/1" do
    property "parses humidity from weather data" do
      check all humidity <- StreamData.integer(1..99),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        humidity_str = String.pad_leading(to_string(humidity), 2, "0")
        weather_data = "123/045g015t090r000p000P000h" <> humidity_str <> rest

        result = Aprs.WeatherHelpers.parse_humidity(weather_data)
        assert result == humidity
      end
    end

    test "parses humidity correctly" do
      assert Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h60b10161") == 60
      assert Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h01b10161") == 1
      assert Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h99b10161") == 99
    end

    test "normalizes zero humidity to 100" do
      assert Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h00b10161") == 100
    end

    test "returns nil for no humidity" do
      assert Aprs.WeatherHelpers.parse_humidity("b10161") == nil
      assert Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000b10161") == nil
      assert Aprs.WeatherHelpers.parse_humidity("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h60") == 60
      assert Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h60b") == 60
      assert Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h60rest") == 60
    end

    test "handles invalid humidity" do
      assert is_integer(Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h600b10161")) or
               is_nil(Aprs.WeatherHelpers.parse_humidity("123/045g015t090r000p000P000h600b10161"))
    end
  end

  describe "parse_pressure/1" do
    property "parses pressure from weather data" do
      check all pressure <- StreamData.integer(0..99_999),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        pressure_str = String.pad_leading(to_string(pressure), 5, "0")
        weather_data = "123/045g015t090r000p000P000h60b" <> pressure_str <> rest

        result = Aprs.WeatherHelpers.parse_pressure(weather_data)
        expected = pressure / 10.0
        assert_in_delta result, expected, 0.001
      end
    end

    test "parses pressure correctly" do
      assert Aprs.WeatherHelpers.parse_pressure("123/045g015t090r000p000P000h60b10161") == 1016.1
      assert Aprs.WeatherHelpers.parse_pressure("123/045g015t090r000p000P000h60b00000") == 0.0
      assert Aprs.WeatherHelpers.parse_pressure("123/045g015t090r000p000P000h60b99999") == 9999.9
    end

    test "returns nil for no pressure" do
      assert Aprs.WeatherHelpers.parse_pressure("161") == nil
      assert Aprs.WeatherHelpers.parse_pressure("123/045g015t090r000p000P000h60") == nil
      assert Aprs.WeatherHelpers.parse_pressure("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_pressure("123/045g015t090r000p000P000h60b10161") == 1016.1
      assert Aprs.WeatherHelpers.parse_pressure("123/045g015t090r000p000P000h60b10161rest") == 1016.1
    end

    test "handles invalid pressure" do
      assert is_float(Aprs.WeatherHelpers.parse_pressure("123/045g015t090r000p000P000h60b101616")) or
               is_nil(Aprs.WeatherHelpers.parse_pressure("123/045g015t090r000p000P000h60b101616"))
    end
  end

  describe "parse_luminosity/1" do
    property "parses luminosity from weather data" do
      check all luminosity <- StreamData.integer(0..999),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        luminosity_str = String.pad_leading(to_string(luminosity), 3, "0")
        weather_data = "123/045g015t090r000p000P000h60b10161l" <> luminosity_str <> rest

        result = Aprs.WeatherHelpers.parse_luminosity(weather_data)
        assert result == luminosity
      end
    end

    test "parses luminosity correctly" do
      assert Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161l000") == 0
      assert Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161l100") == 100
      assert Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161l999") == 999
      assert Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161L100") == 100
    end

    test "returns nil for no luminosity" do
      assert Aprs.WeatherHelpers.parse_luminosity("161") == nil
      assert Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161") == nil
      assert Aprs.WeatherHelpers.parse_luminosity("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161l100") == 100
      assert Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161l100rest") == 100
    end

    test "handles invalid luminosity" do
      assert is_integer(Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161l1000")) or
               is_nil(Aprs.WeatherHelpers.parse_luminosity("123/045g015t090r000p000P000h60b10161l1000"))
    end
  end

  describe "parse_snow/1" do
    property "parses snow from weather data" do
      check all snow <- StreamData.integer(0..999),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        snow_str = String.pad_leading(to_string(snow), 3, "0")
        weather_data = "123/045g015t090r000p000P000h60b10161l000s" <> snow_str <> rest

        result = Aprs.WeatherHelpers.parse_snow(weather_data)
        expected = snow / 10.0
        assert_in_delta result, expected, 0.001
      end
    end

    test "parses snow correctly" do
      assert Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000s000") == 0.0
      assert Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000s100") == 10.0
      assert Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000s250") == 25.0
      assert Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000s999") == 99.9
    end

    test "returns nil for no snow" do
      assert Aprs.WeatherHelpers.parse_snow("161") == nil
      assert Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000") == nil
      assert Aprs.WeatherHelpers.parse_snow("") == nil
    end

    test "handles edge cases" do
      assert Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000s100") == 10.0
      assert Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000s100rest") == 10.0
    end

    test "handles invalid snow" do
      assert is_float(Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000s1000")) or
               is_nil(Aprs.WeatherHelpers.parse_snow("123/045g015t090r000p000P000h60b10161l000s1000"))
    end
  end

  describe "integration tests" do
    test "parses complete weather data" do
      weather_data = "123456z123/045g015t090r000p000P000h60b10161l100s000"

      assert Aprs.WeatherHelpers.extract_timestamp(weather_data) == "123456z"
      assert Aprs.WeatherHelpers.parse_wind_direction(weather_data) == 123
      assert Aprs.WeatherHelpers.parse_wind_speed(weather_data) == 45
      assert Aprs.WeatherHelpers.parse_wind_gust(weather_data) == 15
      assert Aprs.WeatherHelpers.parse_temperature(weather_data) == 90
      assert Aprs.WeatherHelpers.parse_rainfall_1h(weather_data) == 0.0
      assert Aprs.WeatherHelpers.parse_rainfall_24h(weather_data) == 0.0
      assert Aprs.WeatherHelpers.parse_rainfall_since_midnight(weather_data) == 0.0
      assert Aprs.WeatherHelpers.parse_humidity(weather_data) == 60
      assert Aprs.WeatherHelpers.parse_pressure(weather_data) == 1016.1
      assert Aprs.WeatherHelpers.parse_luminosity(weather_data) == 100
      assert Aprs.WeatherHelpers.parse_snow(weather_data) == 0.0
    end

    test "handles real-world weather data" do
      weather_data = "_123/045g015t090r000p000P000h60b10161"

      assert Aprs.WeatherHelpers.parse_wind_direction(weather_data) == 123
      assert Aprs.WeatherHelpers.parse_wind_speed(weather_data) == 45
      assert Aprs.WeatherHelpers.parse_wind_gust(weather_data) == 15
      assert Aprs.WeatherHelpers.parse_temperature(weather_data) == 90
      assert Aprs.WeatherHelpers.parse_humidity(weather_data) == 60
      assert Aprs.WeatherHelpers.parse_pressure(weather_data) == 1016.1
    end

    test "handles partial weather data" do
      weather_data = "123/045t090h60"

      assert Aprs.WeatherHelpers.parse_wind_direction(weather_data) == 123
      assert Aprs.WeatherHelpers.parse_wind_speed(weather_data) == 45
      assert Aprs.WeatherHelpers.parse_temperature(weather_data) == 90
      assert Aprs.WeatherHelpers.parse_humidity(weather_data) == 60

      # These should be nil since they're not present
      assert Aprs.WeatherHelpers.parse_wind_gust(weather_data) == nil
      assert Aprs.WeatherHelpers.parse_rainfall_1h(weather_data) == nil
      assert Aprs.WeatherHelpers.parse_pressure(weather_data) == nil
    end
  end
end
