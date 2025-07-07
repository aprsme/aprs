defmodule Aprs.ConvertTest do
  use ExUnit.Case

  alias Aprs.Convert

  describe "wind/3" do
    test "converts ultimeter wind speed to mph" do
      # Test various wind speeds
      assert Convert.wind(100, :ultimeter, :mph) == 6.21371192
      assert Convert.wind(0, :ultimeter, :mph) == 0.0
      assert Convert.wind(500, :ultimeter, :mph) == 31.0685596
      assert Convert.wind(1000, :ultimeter, :mph) == 62.1371192
    end

    test "handles decimal values" do
      assert_in_delta Convert.wind(123.45, :ultimeter, :mph), 7.67071246524, 0.001
      assert_in_delta Convert.wind(0.5, :ultimeter, :mph), 0.0310685596, 0.0001
    end

    test "handles negative values" do
      assert_in_delta Convert.wind(-100, :ultimeter, :mph), -6.21371192, 0.0001
      assert_in_delta Convert.wind(-50.5, :ultimeter, :mph), -3.1379244696, 0.0001
    end

    test "handles very large values" do
      assert_in_delta Convert.wind(9999, :ultimeter, :mph), 621.3151199208, 0.01
      assert_in_delta Convert.wind(100000, :ultimeter, :mph), 6213.71192, 0.01
    end

    test "handles very small values" do
      assert_in_delta Convert.wind(0.001, :ultimeter, :mph), 0.0000621371192, 0.0000001
      assert_in_delta Convert.wind(0.0001, :ultimeter, :mph), 0.00000621371192, 0.0000001
    end
  end

  describe "temp/3" do
    test "converts ultimeter temperature to fahrenheit" do
      # Test various temperature values
      assert Convert.temp(100, :ultimeter, :f) == 10.0
      assert Convert.temp(0, :ultimeter, :f) == 0.0
      assert Convert.temp(500, :ultimeter, :f) == 50.0
      assert Convert.temp(1000, :ultimeter, :f) == 100.0
    end

    test "handles decimal values" do
      assert Convert.temp(123.45, :ultimeter, :f) == 12.345
      assert Convert.temp(0.5, :ultimeter, :f) == 0.05
    end

    test "handles negative values" do
      assert_in_delta Convert.temp(-100, :ultimeter, :f), -10.0, 0.0001
      assert_in_delta Convert.temp(-50.5, :ultimeter, :f), -5.05, 0.0001
    end

    test "handles very large values" do
      assert_in_delta Convert.temp(9999, :ultimeter, :f), 999.9, 0.0001
      assert_in_delta Convert.temp(100000, :ultimeter, :f), 10000.0, 0.0001
    end

    test "handles very small values" do
      assert Convert.temp(0.001, :ultimeter, :f) == 0.0001
      assert Convert.temp(0.0001, :ultimeter, :f) == 0.00001
    end

    test "handles extreme temperatures" do
      # Test temperatures that might be encountered in real weather data
      assert Convert.temp(2120, :ultimeter, :f) == 212.0  # Boiling point
      assert Convert.temp(-320, :ultimeter, :f) == -32.0  # Freezing point
      assert Convert.temp(10000, :ultimeter, :f) == 1000.0  # Very hot
      assert Convert.temp(-5000, :ultimeter, :f) == -500.0  # Very cold
    end
  end

  describe "speed/3" do
    test "converts knots to mph" do
      # Test various speed values
      assert Convert.speed(1, :knots, :mph) == 1.15
      assert Convert.speed(0, :knots, :mph) == 0.0
      assert Convert.speed(10, :knots, :mph) == 11.51
      assert Convert.speed(100, :knots, :mph) == 115.08
    end

    test "handles decimal values" do
      assert Convert.speed(5.5, :knots, :mph) == 6.33
      assert Convert.speed(0.5, :knots, :mph) == 0.58
    end

    test "handles negative values" do
      assert Convert.speed(-10, :knots, :mph) == -11.51
      assert Convert.speed(-5.5, :knots, :mph) == -6.33
    end

    test "handles very large values" do
      assert Convert.speed(1000, :knots, :mph) == 1150.78
      assert Convert.speed(5000, :knots, :mph) == 5753.90
    end

    test "handles very small values" do
      assert Convert.speed(0.001, :knots, :mph) == 0.00
      assert Convert.speed(0.01, :knots, :mph) == 0.01
    end

    test "rounds to 2 decimal places" do
      # Test that the function properly rounds to 2 decimal places
      assert Convert.speed(1.23456789, :knots, :mph) == 1.42
      assert Convert.speed(10.98765432, :knots, :mph) == 12.64
    end

    test "handles extreme speeds" do
      # Test speeds that might be encountered in aviation or marine contexts
      assert Convert.speed(500, :knots, :mph) == 575.39  # High-speed aircraft
      assert Convert.speed(0.1, :knots, :mph) == 0.12   # Very slow drift
      assert Convert.speed(10000, :knots, :mph) == 11507.79  # Hypersonic
    end
  end

  describe "edge cases and error handling" do
    test "handles zero values for all functions" do
      assert Convert.wind(0, :ultimeter, :mph) == 0.0
      assert Convert.temp(0, :ultimeter, :f) == 0.0
      assert Convert.speed(0, :knots, :mph) == 0.0
    end

    test "handles very small positive values" do
      assert Convert.wind(0.000001, :ultimeter, :mph) == 0.0000000621371192
      assert Convert.temp(0.000001, :ultimeter, :f) == 0.0000001
      assert Convert.speed(0.000001, :knots, :mph) == 0.00
    end

    test "handles very large positive values" do
      assert_in_delta Convert.wind(999999, :ultimeter, :mph), 62136.1199208, 1.0
      assert_in_delta Convert.temp(999999, :ultimeter, :f), 99999.9, 0.0001
      assert_in_delta Convert.speed(999999, :knots, :mph), 1150778.45, 1.0
    end

    test "handles very large negative values" do
      assert_in_delta Convert.wind(-999999, :ultimeter, :mph), -62136.1199208, 1.0
      assert_in_delta Convert.temp(-999999, :ultimeter, :f), -99999.9, 0.0001
      assert_in_delta Convert.speed(-999999, :knots, :mph), -1150778.45, 1.0
    end
  end

  describe "real-world scenarios" do
    test "typical weather station data" do
      # Simulate typical weather station readings
      wind_speed = 150  # ultimeter units
      temperature = 750  # ultimeter units (75.0°F)
      wind_speed_mph = Convert.wind(wind_speed, :ultimeter, :mph)
      temperature_f = Convert.temp(temperature, :ultimeter, :f)

      assert_in_delta wind_speed_mph, 9.32056688, 0.0001
      assert temperature_f == 75.0
    end

    test "marine navigation speeds" do
      # Simulate typical boat speeds
      boat_speed_knots = 15.5
      boat_speed_mph = Convert.speed(boat_speed_knots, :knots, :mph)

      assert boat_speed_mph == 17.84
    end

    test "aviation speeds" do
      # Simulate aircraft speeds
      aircraft_speed_knots = 450
      aircraft_speed_mph = Convert.speed(aircraft_speed_knots, :knots, :mph)

      assert aircraft_speed_mph == 517.85
    end

    test "extreme weather conditions" do
      # Simulate extreme weather readings
      hurricane_wind = 5000  # ultimeter units
      extreme_temp = 1200    # ultimeter units (120.0°F)

      hurricane_wind_mph = Convert.wind(hurricane_wind, :ultimeter, :mph)
      extreme_temp_f = Convert.temp(extreme_temp, :ultimeter, :f)

      assert hurricane_wind_mph == 310.685596
      assert extreme_temp_f == 120.0
    end
  end
end
