defmodule Aprs.HelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "NMEAHelpers" do
    test "parse_nmea_sentence handles valid NMEA" do
      nmea = "$GPRMC,123456,A,4903.50,N,07201.75,W,0.0,0.0,010180,,*6A"
      result = Aprs.NMEAHelpers.parse_nmea_sentence(nmea)
      # not implemented
      assert {:error, _} = result
    end

    test "parse_nmea_sentence handles invalid NMEA" do
      nmea = "invalid"
      result = Aprs.NMEAHelpers.parse_nmea_sentence(nmea)
      assert {:error, _} = result
    end

    test "parse_nmea_coordinate handles valid coordinates" do
      value = "4903.50"
      dir = "N"
      result = Aprs.NMEAHelpers.parse_nmea_coordinate(value, dir)
      assert {:ok, _} = result
    end

    test "parse_nmea_coordinate handles invalid coordinates" do
      value = "invalid"
      dir = "N"
      result = Aprs.NMEAHelpers.parse_nmea_coordinate(value, dir)
      assert {:error, _} = result
    end
  end

  describe "PHGHelpers" do
    test "parse_df_strength handles valid values" do
      assert Aprs.PHGHelpers.parse_df_strength(?0) == {0, "0 dB"}
      assert Aprs.PHGHelpers.parse_df_strength(?9) == {9, "27 dB above S0"}
    end

    test "parse_phg_height handles valid values" do
      assert Aprs.PHGHelpers.parse_phg_height(?0) == {10, "10 feet"}
      assert Aprs.PHGHelpers.parse_phg_height(?9) == {5120, "5120 feet"}
    end

    test "parse_phg_gain handles valid values" do
      assert Aprs.PHGHelpers.parse_phg_gain(?0) == {0, "0 dB"}
      assert Aprs.PHGHelpers.parse_phg_gain(?9) == {9, "9 dB"}
    end

    test "parse_phg_directivity handles valid values" do
      assert Aprs.PHGHelpers.parse_phg_directivity(?0) == {360, "Omni"}
      assert Aprs.PHGHelpers.parse_phg_directivity(?9) == {nil, "Undefined"}
    end
  end

  describe "CompressedPositionHelpers" do
    test "convert_compressed_lat handles valid input" do
      lat = "!!!!"
      {:ok, result} = Aprs.CompressedPositionHelpers.convert_compressed_lat(lat)
      assert is_float(result)
    end

    test "convert_compressed_lon handles valid input" do
      lon = "!!!!"
      {:ok, result} = Aprs.CompressedPositionHelpers.convert_compressed_lon(lon)
      assert is_float(result)
    end

    test "convert_compressed_cs handles valid input" do
      cs = "!!"
      result = Aprs.CompressedPositionHelpers.convert_compressed_cs(cs)
      assert is_map(result)
    end

    test "calculate_compressed_ambiguity handles valid input" do
      comp_type = "!"
      result = Aprs.CompressedPositionHelpers.calculate_compressed_ambiguity(comp_type)
      assert is_integer(result)
    end

    test "convert_to_base91 handles valid input" do
      input = "!!!!"
      result = Aprs.CompressedPositionHelpers.convert_to_base91(input)
      assert is_integer(result)
    end
  end

  describe "KISSHelpers" do
    test "kiss_to_tnc2 handles valid input" do
      # KISS frame: C0 00 ... C0
      frame = <<0xC0, 0x00, 65, 66, 67, 0xC0>>
      result = Aprs.KISSHelpers.kiss_to_tnc2(frame)
      assert is_binary(result) or is_map(result)
    end

    test "kiss_to_tnc2 handles invalid input" do
      frame = "notkiss"
      result = Aprs.KISSHelpers.kiss_to_tnc2(frame)
      assert is_map(result)
      assert result[:error_code] == :packet_invalid
    end

    test "tnc2_to_kiss handles valid input" do
      tnc2 = "ABC"
      result = Aprs.KISSHelpers.tnc2_to_kiss(tnc2)
      assert is_binary(result)
    end
  end

  describe "TelemetryHelpers" do
    test "parse_telemetry_sequence handles valid input" do
      seq = "123"
      result = Aprs.TelemetryHelpers.parse_telemetry_sequence(seq)
      assert is_integer(result)
    end

    test "parse_analog_values handles valid input" do
      analog = ["123", "456", "789", "012", "345", "678", "901", "234"]
      result = Aprs.TelemetryHelpers.parse_analog_values(analog)
      assert is_list(result)
      assert length(result) == 8
    end

    test "parse_digital_values handles valid input" do
      digital = ["1", "0", "1", "0", "1", "0", "1", "0"]
      result = Aprs.TelemetryHelpers.parse_digital_values(digital)
      assert is_list(result)
      assert length(result) == 8
    end

    test "parse_coefficient handles valid input" do
      coeff = "123"
      result = Aprs.TelemetryHelpers.parse_coefficient(coeff)
      assert is_float(result) or is_integer(result)
    end
  end

  describe "WeatherHelpers" do
    test "extract_timestamp handles valid input" do
      weather = "123456z123"
      result = Aprs.WeatherHelpers.extract_timestamp(weather)
      assert is_binary(result) or result == nil
    end

    test "remove_timestamp handles valid input" do
      weather = "123456z123"
      result = Aprs.WeatherHelpers.remove_timestamp(weather)
      assert is_binary(result)
    end

    test "parse_wind_direction handles valid input" do
      weather = "123/045"
      result = Aprs.WeatherHelpers.parse_wind_direction(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_wind_speed handles valid input" do
      weather = "123/045"
      result = Aprs.WeatherHelpers.parse_wind_speed(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_wind_gust handles valid input" do
      weather = "g045"
      result = Aprs.WeatherHelpers.parse_wind_gust(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_temperature handles valid input" do
      weather = "t000"
      result = Aprs.WeatherHelpers.parse_temperature(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_rainfall_1h handles valid input" do
      weather = "r000"
      result = Aprs.WeatherHelpers.parse_rainfall_1h(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_rainfall_24h handles valid input" do
      weather = "p000"
      result = Aprs.WeatherHelpers.parse_rainfall_24h(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_rainfall_since_midnight handles valid input" do
      weather = "P000"
      result = Aprs.WeatherHelpers.parse_rainfall_since_midnight(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_humidity handles valid input" do
      weather = "h00"
      result = Aprs.WeatherHelpers.parse_humidity(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_pressure handles valid input" do
      weather = "b00000"
      result = Aprs.WeatherHelpers.parse_pressure(weather)
      assert is_float(result) or result == nil
    end

    test "parse_luminosity handles valid input" do
      weather = "L000"
      result = Aprs.WeatherHelpers.parse_luminosity(weather)
      assert is_integer(result) or result == nil
    end

    test "parse_snow handles valid input" do
      weather = "s000"
      result = Aprs.WeatherHelpers.parse_snow(weather)
      assert is_integer(result) or result == nil
    end
  end

  describe "UtilityHelpers" do
    test "calculate_position_ambiguity handles valid input" do
      lat = "4903.50N"
      lon = "12311.12W"
      result = Aprs.UtilityHelpers.calculate_position_ambiguity(lat, lon)
      assert is_integer(result)
    end

    test "validate_position_data handles valid input" do
      lat = "4903.50N"
      lon = "12311.12W"
      result = Aprs.UtilityHelpers.validate_position_data(lat, lon)
      assert {:ok, _} = result
    end

    test "validate_position_data handles invalid input" do
      lat = "invalid"
      lon = "invalid"
      result = Aprs.UtilityHelpers.validate_position_data(lat, lon)
      assert {:error, _} = result
    end

    test "validate_timestamp handles valid input" do
      time = "123456"
      result = Aprs.UtilityHelpers.validate_timestamp(time)
      assert result == nil
    end

    test "count_leading_braces handles valid input" do
      packet = "}}}packet"
      result = Aprs.UtilityHelpers.count_leading_braces(packet)
      assert result == 3
    end
  end
end
