defmodule Aprs.ParserUnitTest do
  use ExUnit.Case, async: true

  describe "parse_aprs_position/2 (via parse_position_without_timestamp)" do
    test "parses valid APRS lat/lon" do
      # 4903.50N/12311.12W>
      result = Aprs.parse_position_without_timestamp("4903.50N/12311.12W>comment")
      assert Float.round(result.latitude, 4) == 49.0583
      assert Float.round(result.longitude, 4) == -123.1853
    end

    test "returns nils for invalid lat/lon" do
      # Test with truly invalid input that can't be parsed as compressed position
      result = Aprs.parse_position_without_timestamp("short")
      assert Map.get(result, :latitude) == nil
      result = Aprs.parse_position_without_timestamp("123")
      assert Map.get(result, :longitude) == nil
    end
  end

  describe "compressed position decoding" do
    test "decodes a compressed position" do
      # 1 symbol table + 4 lat + 4 lon + 1 symbol code + 2 cs + 1 type + comment
      pos = Aprs.parse_position_without_timestamp("/!!!!!!!!>abcx")

      assert pos.latitude == 90.0
      assert pos.longitude == -180.0
      assert pos.symbol_code == ">"
      assert pos.format == :compressed
    end
  end

  describe "timestamped position with weather" do
    test "returns map with lat/lon and weather" do
      {:ok, parsed} = Aprs.parse("N0CALL>APRS:@201750z4916.45N/12311.12W_c000s000g005t077")
      result = parsed.data_extended

      assert Float.round(result.latitude, 4) == 49.2742
      assert Float.round(result.longitude, 4) == -123.1853
      assert result.weather
      assert result.weather.temperature == 77
      assert is_integer(result.timestamp)
    end
  end

  describe "parse_data/3 fallback branches" do
    test "raw_gps_ultimeter returns error map" do
      result =
        Aprs.parse_data(:raw_gps_ultimeter, "", "$GPRMC,123456,A,4903.50,N,07201.75,W*6A")

      assert result.data_type == :raw_gps_ultimeter
      assert result.error
    end

    test "df_report fallback" do
      result = Aprs.parse_data(:df_report, "", "notdfsdata")
      assert result.data_type == :df_report
      assert result.df_data == "notdfsdata"
    end

    test "phg_data fallback" do
      result = Aprs.parse_data(:phg_data, "", "notphgdata")
      assert is_map(result)
    end
  end

  describe "parse_position_without_timestamp/1 fallback" do
    test "malformed input returns malformed_position" do
      result = Aprs.parse_position_without_timestamp("badinput")
      assert result.data_type == :malformed_position
      assert Map.get(result, :latitude) == nil
      assert Map.get(result, :longitude) == nil
    end
  end

  describe "parse_position_with_timestamp/3 fallback" do
    test "malformed input returns error map" do
      result = Aprs.parse_position_with_timestamp(false, "badinput", :timestamped_position)
      assert result.data_type == :timestamped_position_error
      assert result.error =~ "Invalid timestamped position format"
    end
  end
end
