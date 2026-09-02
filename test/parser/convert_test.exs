defmodule Aprs.ConvertTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Convert

  doctest Convert

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

  describe "edge cases" do
    test "handles zero values" do
      assert Convert.wind(0, :ultimeter, :mph) == 0.0
      assert Convert.temp(0, :ultimeter, :f) == 0.0
    end

    test "handles large values" do
      assert Convert.wind(10_000, :ultimeter, :mph) == 621.371192
      assert Convert.temp(10_000, :ultimeter, :f) == 1000.0
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
  end
end
