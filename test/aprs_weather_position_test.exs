defmodule Aprs.WeatherPositionTest do
  use ExUnit.Case, async: true

  describe "timestamped position with weather data" do
    test "parses weather data from timestamped position packet" do
      # This is the packet from the user's issue
      raw_packet =
        "KE5WTH-14>APN000,TCPIP*,qAC,T2CHILE:@281640z3315.65N/09644.23W_235/005g010t088r000p000P000b10183h64L069eMB62"

      {:ok, parsed} = Aprs.parse(raw_packet)

      # FAP-compatible: @ prefix → timestamped_position_with_message, not :weather
      # Only the _ data type indicator produces :weather
      assert parsed.data_type == :timestamped_position_with_message

      # Position data in data_extended
      assert parsed.data_extended.latitude
      assert parsed.data_extended.longitude
      assert is_integer(parsed.data_extended.time)

      # Weather data extracted into wx (FAP-compatible behavior for /_  symbol)
      wx = parsed.wx
      assert wx[:temperature] == 88
      assert wx[:humidity] == 64
      assert wx[:wind_direction] == 235
      assert wx[:wind_speed] == 5
      assert wx[:wind_gust] == 10
      assert wx[:pressure] == 1018.3
      assert wx[:luminosity] == 69
    end

    test "parses weather data from timestamped position with different weather format" do
      raw_packet = "TEST-1>APRS,WIDE1-1:@281640z3315.65N/09644.23W_180/010g015t072r000p000h45b10132"

      {:ok, parsed} = Aprs.parse(raw_packet)

      # FAP-compatible: @ prefix → timestamped_position_with_message
      assert parsed.data_type == :timestamped_position_with_message

      assert parsed.data_extended.latitude
      assert parsed.data_extended.longitude
      assert is_integer(parsed.data_extended.time)

      # Weather data extracted into wx
      wx = parsed.wx
      assert wx[:temperature] == 72
      assert wx[:humidity] == 45
      assert wx[:wind_direction] == 180
      assert wx[:wind_speed] == 10
      assert wx[:wind_gust] == 15
      assert wx[:pressure] == 1013.2
    end

    test "handles timestamped position without weather data" do
      raw_packet = "TEST-1>APRS,WIDE1-1:@281640z3315.65N/09644.23W>Test comment"

      {:ok, parsed} = Aprs.parse(raw_packet)

      assert parsed.data_type == :timestamped_position_with_message

      # Should have position and comment
      weather_data = parsed.data_extended
      assert weather_data.latitude
      assert weather_data.longitude
      assert is_integer(weather_data.time)
      assert weather_data.comment == "Test comment"
    end
  end
end
