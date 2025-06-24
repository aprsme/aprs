defmodule AprsParser.HelpersTest do
  use ExUnit.Case, async: true

  describe "NMEA helpers" do
    test "parse_nmea_coordinate parses valid coordinates" do
      assert AprsParser.NMEAHelpers.parse_nmea_coordinate("4916.45", "N") == {:ok, 49.1645}
      {:ok, val} = AprsParser.NMEAHelpers.parse_nmea_coordinate("12311.12", "W")
      assert_in_delta val, -123.1112, 1.0e-6
    end

    test "parse_nmea_coordinate errors on invalid input" do
      assert AprsParser.NMEAHelpers.parse_nmea_coordinate("bad", "N") ==
               {:error, "Invalid coordinate value"}

      assert AprsParser.NMEAHelpers.parse_nmea_coordinate("4916.45", "Q") ==
               {:error, "Invalid coordinate direction"}

      assert AprsParser.NMEAHelpers.parse_nmea_coordinate(nil, nil) ==
               {:error, "Invalid coordinate format"}
    end

    test "parse_nmea_sentence returns not implemented" do
      assert AprsParser.NMEAHelpers.parse_nmea_sentence("anything") ==
               {:error, "NMEA parsing not implemented"}
    end
  end

  describe "PHG/DF helpers" do
    test "parse_phg_power returns correct values" do
      assert AprsParser.PHGHelpers.parse_phg_power(?0) == {1, "1 watt"}
      assert AprsParser.PHGHelpers.parse_phg_power(?9) == {81, "81 watts"}
      assert AprsParser.PHGHelpers.parse_phg_power(?X) == {nil, "Unknown power: X"}
    end

    test "parse_phg_height returns correct values" do
      assert AprsParser.PHGHelpers.parse_phg_height(?0) == {10, "10 feet"}
      assert AprsParser.PHGHelpers.parse_phg_height(?9) == {5120, "5120 feet"}
      assert AprsParser.PHGHelpers.parse_phg_height(?X) == {nil, "Unknown height: X"}
    end

    test "parse_phg_gain returns correct values" do
      assert AprsParser.PHGHelpers.parse_phg_gain(?0) == {0, "0 dB"}
      assert AprsParser.PHGHelpers.parse_phg_gain(?9) == {9, "9 dB"}
      assert AprsParser.PHGHelpers.parse_phg_gain(?X) == {nil, "Unknown gain: X"}
    end

    test "parse_phg_directivity returns correct values" do
      assert AprsParser.PHGHelpers.parse_phg_directivity(?0) == {360, "Omni"}
      assert AprsParser.PHGHelpers.parse_phg_directivity(?9) == {nil, "Undefined"}
      assert AprsParser.PHGHelpers.parse_phg_directivity(?X) == {nil, "Unknown directivity: X"}
    end

    test "parse_df_strength returns correct values" do
      assert AprsParser.PHGHelpers.parse_df_strength(?0) == {0, "0 dB"}
      assert AprsParser.PHGHelpers.parse_df_strength(?9) == {9, "27 dB above S0"}
      assert AprsParser.PHGHelpers.parse_df_strength(?X) == {nil, "Unknown strength: X"}
    end
  end

  describe "compressed position helpers" do
    test "convert_compressed_lat and lon handle valid input" do
      {:ok, lat} = AprsParser.CompressedPositionHelpers.convert_compressed_lat("9RZV")
      {:ok, lon} = AprsParser.CompressedPositionHelpers.convert_compressed_lon("9RZV")
      assert is_float(lat)
      assert is_float(lon)
      assert lat >= -90 and lat <= 90
      assert lon >= -180 and lon <= 180
    end

    test "convert_compressed_lat and lon return error for invalid input" do
      assert AprsParser.CompressedPositionHelpers.convert_compressed_lat("abcde") ==
               {:error, "Invalid compressed latitude"}

      assert AprsParser.CompressedPositionHelpers.convert_compressed_lon("abcde") ==
               {:error, "Invalid compressed longitude"}

      assert AprsParser.CompressedPositionHelpers.convert_compressed_lat(123) ==
               {:error, "Invalid compressed latitude"}

      assert AprsParser.CompressedPositionHelpers.convert_compressed_lon(123) ==
               {:error, "Invalid compressed longitude"}
    end
  end

  describe "KISS/TNC2 utilities" do
    test "kiss_to_tnc2 decodes KISS frames" do
      frame = <<0xC0, 0x00, 65, 66, 67, 0xC0>>
      assert AprsParser.KISSHelpers.kiss_to_tnc2(frame) == "ABC"

      frame = <<0xC0, 0x00, 0x41, 0xDB, 0xDC, 0x42, 0xDB, 0xDD, 0x43, 0xC0>>
      assert AprsParser.KISSHelpers.kiss_to_tnc2(frame) == "A\xC0B\xDB" <> "C"
    end

    test "kiss_to_tnc2 returns error for invalid frame" do
      assert AprsParser.KISSHelpers.kiss_to_tnc2("notkiss") == %{
               error_code: :packet_invalid,
               error_message: "Unknown error"
             }
    end

    test "tnc2_to_kiss encodes TNC2 to KISS" do
      tnc2 = "A\xDBB\xC0C"
      kiss = AprsParser.KISSHelpers.tnc2_to_kiss(tnc2)
      assert :binary.part(kiss, 0, 1) == <<0xC0>>
      assert :binary.part(kiss, byte_size(kiss) - 1, 1) == <<0xC0>>
    end
  end

  describe "telemetry helpers" do
    test "parse_telemetry_sequence parses valid values" do
      assert AprsParser.TelemetryHelpers.parse_telemetry_sequence("123") == 123
      assert AprsParser.TelemetryHelpers.parse_telemetry_sequence("abc") == nil
    end

    test "parse_analog_values parses valid values" do
      assert AprsParser.TelemetryHelpers.parse_analog_values(["1.23", "4.56", ""]) == [
               1.23,
               4.56,
               nil
             ]

      assert AprsParser.TelemetryHelpers.parse_analog_values(["abc", "1.23"]) == [nil, 1.23]
    end

    test "parse_digital_values parses valid values" do
      assert AprsParser.TelemetryHelpers.parse_digital_values(["101"]) == [true, false, true]
      assert AprsParser.TelemetryHelpers.parse_digital_values(["1", "0"]) == [true, false]
      assert AprsParser.TelemetryHelpers.parse_digital_values(["abc"]) == [nil, nil, nil]
      assert AprsParser.TelemetryHelpers.parse_digital_values([123]) == [nil]
    end

    test "parse_coefficient parses valid values" do
      assert AprsParser.TelemetryHelpers.parse_coefficient("1.23") == 1.23
      assert AprsParser.TelemetryHelpers.parse_coefficient("123") == 123
      assert AprsParser.TelemetryHelpers.parse_coefficient("abc") == "abc"
    end
  end

  describe "weather helpers" do
    test "extract_timestamp handles valid formats" do
      assert AprsParser.WeatherHelpers.extract_timestamp("092345z123") == "092345z"
      assert AprsParser.WeatherHelpers.extract_timestamp("092345h123") == "092345h"
      assert AprsParser.WeatherHelpers.extract_timestamp("092345/123") == "092345/"
      assert AprsParser.WeatherHelpers.extract_timestamp("12345") == nil
    end

    test "remove_timestamp removes timestamp when present" do
      assert AprsParser.WeatherHelpers.remove_timestamp("092345z123") == "123"
      assert AprsParser.WeatherHelpers.remove_timestamp("092345h456") == "456"
      assert AprsParser.WeatherHelpers.remove_timestamp("092345/789") == "789"
      assert AprsParser.WeatherHelpers.remove_timestamp("12345") == "12345"
    end

    test "parse_wind_direction extracts direction" do
      assert AprsParser.WeatherHelpers.parse_wind_direction("123/045") == 123
      assert AprsParser.WeatherHelpers.parse_wind_direction("invalid") == nil
    end

    test "parse_wind_speed extracts speed" do
      assert AprsParser.WeatherHelpers.parse_wind_speed("123/045") == 45
      assert AprsParser.WeatherHelpers.parse_wind_speed("invalid") == nil
    end

    test "parse_wind_gust extracts gust speed" do
      assert AprsParser.WeatherHelpers.parse_wind_gust("g045") == 45
      assert AprsParser.WeatherHelpers.parse_wind_gust("invalid") == nil
    end

    test "parse_temperature extracts temperature" do
      assert AprsParser.WeatherHelpers.parse_temperature("t072") == 72
      assert AprsParser.WeatherHelpers.parse_temperature("invalid") == nil
    end

    test "parse_rainfall_1h extracts rainfall" do
      assert AprsParser.WeatherHelpers.parse_rainfall_1h("r010") == 10
      assert AprsParser.WeatherHelpers.parse_rainfall_1h("invalid") == nil
    end

    test "parse_rainfall_24h extracts rainfall" do
      assert AprsParser.WeatherHelpers.parse_rainfall_24h("p024") == 24
      assert AprsParser.WeatherHelpers.parse_rainfall_24h("invalid") == nil
    end

    test "parse_rainfall_since_midnight extracts rainfall" do
      assert AprsParser.WeatherHelpers.parse_rainfall_since_midnight("P036") == 36
      assert AprsParser.WeatherHelpers.parse_rainfall_since_midnight("invalid") == nil
    end

    test "parse_humidity extracts humidity" do
      assert AprsParser.WeatherHelpers.parse_humidity("h00") == 100
      assert AprsParser.WeatherHelpers.parse_humidity("h75") == 75
      assert AprsParser.WeatherHelpers.parse_humidity("invalid") == nil
    end

    test "parse_pressure extracts pressure" do
      assert AprsParser.WeatherHelpers.parse_pressure("b10150") == 1015.0
      assert AprsParser.WeatherHelpers.parse_pressure("invalid") == nil
    end

    test "parse_luminosity extracts luminosity" do
      assert AprsParser.WeatherHelpers.parse_luminosity("l123") == 123
      assert AprsParser.WeatherHelpers.parse_luminosity("L456") == 456
      assert AprsParser.WeatherHelpers.parse_luminosity("invalid") == nil
    end

    test "parse_snow extracts snow depth" do
      assert AprsParser.WeatherHelpers.parse_snow("s012") == 12
      assert AprsParser.WeatherHelpers.parse_snow("invalid") == nil
    end
  end

  describe "PEET logging helpers" do
    test "parse_peet_logging handles data with and without prefix" do
      assert AprsParser.SpecialDataHelpers.parse_peet_logging("*1234") == %{
               peet_data: "1234",
               data_type: :peet_logging
             }

      assert AprsParser.SpecialDataHelpers.parse_peet_logging("1234") == %{
               peet_data: "1234",
               data_type: :peet_logging
             }
    end
  end

  describe "invalid/test data helpers" do
    test "parse_invalid_test_data handles data with and without comma" do
      assert AprsParser.SpecialDataHelpers.parse_invalid_test_data(",1234") == %{
               test_data: "1234",
               data_type: :invalid_test_data
             }

      assert AprsParser.SpecialDataHelpers.parse_invalid_test_data("1234") == %{
               test_data: "1234",
               data_type: :invalid_test_data
             }
    end
  end

  describe "utility helpers" do
    test "count_spaces counts spaces correctly" do
      assert AprsParser.UtilityHelpers.count_spaces("a b c") == 2
      assert AprsParser.UtilityHelpers.count_spaces("abc") == 0
      assert AprsParser.UtilityHelpers.count_spaces(" ") == 1
    end

    test "count_leading_braces counts braces correctly" do
      assert AprsParser.UtilityHelpers.count_leading_braces("}}abc") == 2
      assert AprsParser.UtilityHelpers.count_leading_braces("abc") == 0
      assert AprsParser.UtilityHelpers.count_leading_braces("}a}bc") == 1
    end

    test "calculate_position_ambiguity determines ambiguity level" do
      assert AprsParser.UtilityHelpers.calculate_position_ambiguity("12 34.56N", "123 45.67W") == 1
      assert AprsParser.UtilityHelpers.calculate_position_ambiguity("12  34.56N", "123  45.67W") == 2

      assert AprsParser.UtilityHelpers.calculate_position_ambiguity("12   34.56N", "123   45.67W") ==
               3

      assert AprsParser.UtilityHelpers.calculate_position_ambiguity("12    34.56N", "123    45.67W") ==
               4

      assert AprsParser.UtilityHelpers.calculate_position_ambiguity("1234.56N", "12345.67W") == 0
    end

    test "calculate_compressed_ambiguity determines compressed ambiguity" do
      assert AprsParser.CompressedPositionHelpers.calculate_compressed_ambiguity(" ") == 0
      assert AprsParser.CompressedPositionHelpers.calculate_compressed_ambiguity("!") == 1
      assert AprsParser.CompressedPositionHelpers.calculate_compressed_ambiguity("\"") == 2
      assert AprsParser.CompressedPositionHelpers.calculate_compressed_ambiguity("#") == 3
      assert AprsParser.CompressedPositionHelpers.calculate_compressed_ambiguity("$") == 4
      assert AprsParser.CompressedPositionHelpers.calculate_compressed_ambiguity("X") == 0
    end

    test "validate_position_data validates positions" do
      assert {:ok, {lat, lon}} =
               AprsParser.UtilityHelpers.validate_position_data("4916.45N", "12311.12W")

      assert_in_delta Decimal.to_float(lat), 49.2742, 0.0001
      assert_in_delta Decimal.to_float(lon), -123.1853, 0.0001

      assert AprsParser.UtilityHelpers.validate_position_data("invalid", "12311.12W") ==
               {:error, :invalid_position}

      assert AprsParser.UtilityHelpers.validate_position_data("4916.45N", "invalid") ==
               {:error, :invalid_position}
    end

    test "validate_timestamp always returns nil" do
      assert AprsParser.UtilityHelpers.validate_timestamp("any") == nil
    end

    test "find_matches handles named and unnamed captures" do
      regex = ~r/(?<val>\d+)/
      assert AprsParser.UtilityHelpers.find_matches(regex, "abc123def") == %{"val" => "123"}

      regex = ~r/(\d+)/
      assert AprsParser.UtilityHelpers.find_matches(regex, "abc123def") == %{0 => "123", 1 => "123"}
    end
  end
end
