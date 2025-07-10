defmodule Aprs.Parser.PositionWithCourseSpeedTest do
  use ExUnit.Case, async: true

  describe "position packets with course/speed" do
    test "KG5GKC-12 position packet with course/speed should be parsed as position" do
      # This packet was being misclassified as weather
      packet = "KG5GKC-12>APAT51,WIDE1-1,WIDE2-2,qAO,NI2C-10:!3310.04N/09640.40Wk038/023/A=000623AT-MOBILE KG5GKC@YAHOO.COM"
      
      {:ok, parsed} = Aprs.parse(packet)
      
      # Should be identified as position
      assert parsed.data_type == :position
      assert parsed.sender == "KG5GKC-12"
      assert parsed.destination == "APAT51"
      
      # Check position data
      assert parsed.data_extended[:latitude]
      assert parsed.data_extended[:longitude]
      assert parsed.data_extended[:symbol_code] == "k"
      assert parsed.data_extended[:symbol_table_id] == "/"
      
      # Check course/speed extraction
      assert parsed.data_extended[:course] == 38
      assert parsed.data_extended[:speed] == 23.0
      
      # Should not have weather fields
      refute parsed.data_extended[:temperature]
      refute parsed.data_extended[:humidity]
      refute parsed.data_extended[:pressure]
      refute parsed.data_extended[:wind_direction]
      refute parsed.data_extended[:wind_speed]
    end

    test "position packet with different symbol should not be weather" do
      # Car symbol (>) with course/speed
      packet = "N0CALL>APRS:!3310.04N/09640.40W>123/045/A=001000"
      
      {:ok, parsed} = Aprs.parse(packet)
      
      assert parsed.data_type == :position
      assert parsed.data_extended[:symbol_code] == ">"
      assert parsed.data_extended[:symbol_table_id] == "/"
      assert parsed.data_extended[:course] == 123
      assert parsed.data_extended[:speed] == 45.0
    end

    test "position with PHG data should not be weather" do
      packet = "N0CALL>APRS:!3310.04N/09640.40W#PHG5130/W3,FLn comment"
      
      {:ok, parsed} = Aprs.parse(packet)
      
      assert parsed.data_type == :position
      assert parsed.data_extended[:symbol_code] == "#"
      assert parsed.data_extended[:comment] =~ "PHG5130"
    end

    test "weather station symbol without weather data is just position" do
      # Weather symbol "_" but no weather data
      packet = "N0CALL>APRS:!3310.04N/09640.40W_No weather data here"
      
      {:ok, parsed} = Aprs.parse(packet)
      
      # Parser correctly identifies as position since no weather data
      assert parsed.data_type == :position
      assert parsed.data_extended[:symbol_code] == "_"
      assert parsed.data_extended[:comment] == "No weather data here"
    end

    test "actual weather packet should be identified as weather" do
      # Real weather format with "_" prefix and weather data
      packet = "KC0ABC>APRS:_10090556c220/004g005t077r000p000P000h50b09900"
      
      {:ok, parsed} = Aprs.parse(packet)
      
      assert parsed.data_type == :weather
      assert parsed.data_extended[:temperature] == 77
      assert parsed.data_extended[:humidity] == 50
      assert parsed.data_extended[:pressure] == 990.0
      # Wind direction/speed parsing requires the xxx/xxx format
      assert parsed.data_extended[:wind_direction] == 220
      assert parsed.data_extended[:wind_speed] == 4
    end

    test "position with weather symbol and weather data extracts both" do
      # Position packet with weather station symbol and weather data patterns
      # This is a position packet that also reports weather
      packet = "N0CALL>APRS:!3310.04N/09640.40W_220/004g005t077r000p000P000h50b09900"
      
      {:ok, parsed} = Aprs.parse(packet)
      
      # Parser identifies as position (because of ! prefix)
      # but also extracts weather data from comment
      assert parsed.data_type == :position
      assert parsed.data_extended[:symbol_code] == "_"
      
      # Weather data is extracted
      assert parsed.data_extended[:temperature] == 77
      assert parsed.data_extended[:humidity] == 50
      assert parsed.data_extended[:pressure] == 990.0
      assert parsed.data_extended[:wind_direction] == 220
      assert parsed.data_extended[:wind_speed] == 4
      
      # Also has position data
      assert parsed.data_extended[:latitude]
      assert parsed.data_extended[:longitude]
    end
  end
end