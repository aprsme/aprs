defmodule Aprs.ConvertTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Convert

  describe "wind/3" do
    test "converts ultimeter wind speed to mph" do
      # Test conversion factor: 0.0621371192
      assert Convert.wind(100, :ultimeter, :mph) == 6.21371192
      assert Convert.wind(50, :ultimeter, :mph) == 3.10685596
      assert Convert.wind(0, :ultimeter, :mph) == 0.0
    end

    property "wind conversion produces positive results for positive input" do
      check all speed <- StreamData.positive_integer() do
        result = Convert.wind(speed, :ultimeter, :mph)
        assert result > 0
        assert is_float(result)
      end
    end

    property "wind conversion is linear" do
      check all speed1 <- StreamData.positive_integer(),
                speed2 <- StreamData.positive_integer() do
        result1 = Convert.wind(speed1, :ultimeter, :mph)
        result2 = Convert.wind(speed2, :ultimeter, :mph)

        # Linear relationship: if speed2 > speed1, result2 > result1
        if speed2 > speed1 do
          assert result2 > result1
        end
      end
    end
  end

  describe "temp/3" do
    test "converts ultimeter temperature to fahrenheit" do
      # Test conversion factor: 0.1
      assert Convert.temp(100, :ultimeter, :f) == 10.0
      assert Convert.temp(250, :ultimeter, :f) == 25.0
      assert Convert.temp(0, :ultimeter, :f) == 0.0
      assert Convert.temp(325, :ultimeter, :f) == 32.5
    end

    test "handles negative temperatures" do
      assert Convert.temp(-100, :ultimeter, :f) == -10.0
      assert Convert.temp(-50, :ultimeter, :f) == -5.0
    end

    property "temperature conversion produces correct scaling" do
      check all temp <- StreamData.integer(-1000..1000) do
        result = Convert.temp(temp, :ultimeter, :f)
        assert result == temp * 0.1
        assert is_float(result)
      end
    end
  end

  describe "speed/3" do
    test "converts knots to mph" do
      # Test conversion factor: 1.15077945, rounded to 2 decimal places
      assert Convert.speed(10, :knots, :mph) == 11.51
      assert Convert.speed(20, :knots, :mph) == 23.02
      assert Convert.speed(0, :knots, :mph) == 0.0
      assert Convert.speed(5, :knots, :mph) == 5.75
    end

    test "handles fractional knots" do
      assert Convert.speed(10.5, :knots, :mph) == 12.08
      assert Convert.speed(2.5, :knots, :mph) == 2.88
    end

    property "speed conversion is always rounded to 2 decimal places" do
      check all speed <- StreamData.float(min: 0.0, max: 1000.0) do
        result = Convert.speed(speed, :knots, :mph)

        # Check that result is rounded to 2 decimal places
        rounded_result = Float.round(result, 2)
        assert result == rounded_result

        # Check conversion factor
        expected = Float.round(speed * 1.15077945, 2)
        assert result == expected
      end
    end

    property "speed conversion produces positive results for positive input" do
      check all speed <- StreamData.float(min: 0.1, max: 1000.0) do
        result = Convert.speed(speed, :knots, :mph)
        assert result >= 0
        assert is_float(result)
      end
    end
  end

  describe "edge cases" do
    test "handles zero values" do
      assert Convert.wind(0, :ultimeter, :mph) == 0.0
      assert Convert.temp(0, :ultimeter, :f) == 0.0
      assert Convert.speed(0, :knots, :mph) == 0.0
    end

    test "handles large values" do
      assert Convert.wind(10_000, :ultimeter, :mph) == 621.371192
      assert Convert.temp(10_000, :ultimeter, :f) == 1000.0
      assert Convert.speed(1000, :knots, :mph) == 1150.78
    end

    test "wind conversion precision" do
      # Test that the exact conversion factor is used
      result = Convert.wind(1, :ultimeter, :mph)
      assert result == 0.0621371192
    end

    test "temperature conversion precision" do
      # Test that the exact conversion factor is used
      result = Convert.temp(1, :ultimeter, :f)
      assert result == 0.1
    end

    test "speed conversion precision and rounding" do
      # Test that the exact conversion factor is used and rounded
      result = Convert.speed(1, :knots, :mph)
      expected = Float.round(1.15077945, 2)
      assert result == expected
    end
  end
end
