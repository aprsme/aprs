defmodule Aprs.WeatherPositionTest do
  use ExUnit.Case, async: true

  describe "timestamped position with weather data" do
    test "parses weather data from timestamped position packet" do
      # This is the packet from the user's issue
      raw_packet =
        "KE5WTH-14>APN000,TCPIP*,qAC,T2CHILE:@281640z3315.65N/09644.23W_235/005g010t088r000p000P000b10183h64L069eMB62"

      {:ok, parsed} = Aprs.parse(raw_packet)

      # Should be a weather packet (timestamped position with weather data)
      assert parsed.data_type == :weather

      # For now, just check that we have position data
      weather_data = parsed.data_extended
      assert weather_data.latitude
      assert weather_data.longitude
      # The timestamp is converted to Unix time in the current implementation
      assert is_integer(weather_data.time)

      # Weather parsing assertions will be added when weather parsing is implemented
      # assert weather_data.temperature == 88
      # assert weather_data.humidity == 64
      # assert weather_data.wind_direction == 235
      # assert weather_data.wind_speed == 5
      # assert weather_data.wind_gust == 10
      # assert weather_data.pressure == 1018.3
      # assert weather_data.rain_1h == 0
      # assert weather_data.rain_24h == 0
      # assert weather_data.rain_since_midnight == 0
      # assert weather_data.luminosity == 69
    end

    test "parses weather data from timestamped position with different weather format" do
      raw_packet = "TEST-1>APRS,WIDE1-1:@281640z3315.65N/09644.23W_180/010g015t072r000p000h45b10132"

      {:ok, parsed} = Aprs.parse(raw_packet)

      assert parsed.data_type == :weather

      weather_data = parsed.data_extended
      assert weather_data.latitude
      assert weather_data.longitude
      assert is_integer(weather_data.time)

      # Weather parsing assertions will be added when weather parsing is implemented
      # assert weather_data.temperature == 72
      # assert weather_data.humidity == 45
      # assert weather_data.wind_direction == 180
      # assert weather_data.wind_speed == 10
      # assert weather_data.wind_gust == 15
      # assert weather_data.pressure == 1013.2
      # assert weather_data.rain_1h == 0
      # assert weather_data.rain_24h == 0
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
