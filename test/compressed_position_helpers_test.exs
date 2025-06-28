defmodule Aprs.CompressedPositionHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias Aprs.CompressedPositionHelpers

  describe "convert_compressed_lat/1" do
    test "converts valid compressed latitude" do
      # Test with known values
      assert {:ok, lat1} = CompressedPositionHelpers.convert_compressed_lat("5L!!")
      assert_in_delta lat1, 56.24, 0.5

      assert {:ok, lat2} = CompressedPositionHelpers.convert_compressed_lat("5B!!")
      assert is_float(lat2)

      # Test minimum and maximum possible values
      assert {:ok, min_lat} = CompressedPositionHelpers.convert_compressed_lat("!!!!")
      assert_in_delta min_lat, 90.0, 0.1

      assert {:ok, max_lat} = CompressedPositionHelpers.convert_compressed_lat("~~~~")
      # Should be negative latitude
      assert max_lat < 0.0
    end

    test "returns error for invalid input" do
      assert {:error, "Invalid compressed latitude"} == CompressedPositionHelpers.convert_compressed_lat("")
      assert {:error, "Invalid compressed latitude"} == CompressedPositionHelpers.convert_compressed_lat("123")
      assert {:error, "Invalid compressed latitude"} == CompressedPositionHelpers.convert_compressed_lat(1234)
      assert {:error, "Invalid compressed latitude"} == CompressedPositionHelpers.convert_compressed_lat(nil)
      assert {:error, "Invalid compressed latitude"} == CompressedPositionHelpers.convert_compressed_lat("12345")
    end
  end

  describe "convert_compressed_lon/1" do
    test "converts valid compressed longitude" do
      # Test with known values
      assert {:ok, lon1} = CompressedPositionHelpers.convert_compressed_lon("7P[!")
      assert is_float(lon1)

      assert {:ok, lon2} = CompressedPositionHelpers.convert_compressed_lon("5B!!")
      assert is_float(lon2)

      # Test minimum and maximum possible values
      assert {:ok, min_lon} = CompressedPositionHelpers.convert_compressed_lon("!!!!")
      assert_in_delta min_lon, -180.0, 0.1

      assert {:ok, max_lon} = CompressedPositionHelpers.convert_compressed_lon("~~~~")
      # Should be positive longitude
      assert max_lon > 0.0
    end

    test "returns error for invalid input" do
      assert {:error, "Invalid compressed longitude"} == CompressedPositionHelpers.convert_compressed_lon("")
      assert {:error, "Invalid compressed longitude"} == CompressedPositionHelpers.convert_compressed_lon("123")
      assert {:error, "Invalid compressed longitude"} == CompressedPositionHelpers.convert_compressed_lon(1234)
      assert {:error, "Invalid compressed longitude"} == CompressedPositionHelpers.convert_compressed_lon(nil)
      assert {:error, "Invalid compressed longitude"} == CompressedPositionHelpers.convert_compressed_lon("12345")
    end
  end

  describe "calculate_compressed_ambiguity/1" do
    test "returns correct ambiguity values" do
      # Test all defined ambiguity values
      assert 0 == CompressedPositionHelpers.calculate_compressed_ambiguity(" ")
      assert 1 == CompressedPositionHelpers.calculate_compressed_ambiguity("!")
      assert 2 == CompressedPositionHelpers.calculate_compressed_ambiguity("\"")
      assert 3 == CompressedPositionHelpers.calculate_compressed_ambiguity("#")
      assert 4 == CompressedPositionHelpers.calculate_compressed_ambiguity("$")

      # Test default case with other characters
      assert 0 == CompressedPositionHelpers.calculate_compressed_ambiguity("@")
      assert 0 == CompressedPositionHelpers.calculate_compressed_ambiguity("A")
      assert 0 == CompressedPositionHelpers.calculate_compressed_ambiguity("z")

      # Test with longer strings (should only look at first character)
      assert 1 == CompressedPositionHelpers.calculate_compressed_ambiguity("!abc")

      # Test with empty string
      assert 0 == CompressedPositionHelpers.calculate_compressed_ambiguity("")
    end
  end

  describe "convert_compressed_cs/1" do
    test "returns course and speed when valid" do
      # Test with minimum values
      result = CompressedPositionHelpers.convert_compressed_cs("!!")
      assert %{course: 0, speed: speed} = result
      assert is_float(speed) and speed >= 0.0

      # Test with maximum values
      result = CompressedPositionHelpers.convert_compressed_cs("z~")
      assert %{course: course, speed: speed} = result
      assert is_integer(course)
      assert is_float(speed)

      # Test with specific known values
      result = CompressedPositionHelpers.convert_compressed_cs("A!")
      assert %{course: 0, speed: speed} = result
      assert speed > 0.0
    end

    test "returns range when first char is Z" do
      # Test with minimum range
      result = CompressedPositionHelpers.convert_compressed_cs("Z!")
      assert %{range: range} = result
      assert range > 0.0

      # Test with maximum range
      result = CompressedPositionHelpers.convert_compressed_cs("Z~")
      assert %{range: range} = result
      assert range > 0.0
    end

    test "returns empty map for invalid input" do
      # Test various invalid inputs
      assert %{} == CompressedPositionHelpers.convert_compressed_cs("")
      assert %{} == CompressedPositionHelpers.convert_compressed_cs("A")
      assert %{} == CompressedPositionHelpers.convert_compressed_cs("ABC")
      assert %{} == CompressedPositionHelpers.convert_compressed_cs(nil)
      assert %{} == CompressedPositionHelpers.convert_compressed_cs(123)
    end
  end

  describe "base91 calculations" do
    test "calculates correct base91 values through public API" do
      # Test with minimum value (all '!' characters)
      {:ok, lat1} = CompressedPositionHelpers.convert_compressed_lat("!!!!")
      assert_in_delta lat1, 90.0, 0.0001

      # Test with maximum value (all '~' characters)
      {:ok, lat2} = CompressedPositionHelpers.convert_compressed_lat("~~~~")
      # Should be negative latitude
      assert lat2 < 0.0

      # Test with known values
      {:ok, lon1} = CompressedPositionHelpers.convert_compressed_lon("!!!!")
      assert_in_delta lon1, -180.0, 0.0001

      # Test with a known compressed coordinate
      {:ok, lat3} = CompressedPositionHelpers.convert_compressed_lat("5L!!")
      assert is_float(lat3)
      assert lat3 > 0.0 and lat3 < 90.0

      # Test with another known value
      {:ok, lon2} = CompressedPositionHelpers.convert_compressed_lon("7P[!")
      assert is_float(lon2)
      assert lon2 > -180.0 and lon2 < 180.0
    end

    test "handles edge cases in base91 calculations" do
      # Test with all possible first characters to ensure no crashes
      for c <- ?!..?~ do
        input = List.to_string([c, c, c, c])
        assert {:ok, _} = CompressedPositionHelpers.convert_compressed_lat(input)
        assert {:ok, _} = CompressedPositionHelpers.convert_compressed_lon(input)
      end
    end
  end

  # Property-based tests for more thorough validation
  property "convert_compressed_lat/1 returns values between -90 and 90 degrees" do
    check all chars <- list_of(integer(33..126), length: 4) do
      input = List.to_string(chars)
      assert {:ok, lat} = CompressedPositionHelpers.convert_compressed_lat(input)
      assert lat >= -90.0
      assert lat <= 90.0
    end
  end

  property "convert_compressed_lon/1 returns values between -180 and 180 degrees" do
    check all chars <- list_of(integer(33..126), length: 4) do
      input = List.to_string(chars)
      assert {:ok, lon} = CompressedPositionHelpers.convert_compressed_lon(input)
      assert lon >= -180.0
      assert lon <= 180.0
    end
  end

  property "convert_compressed_cs/1 returns expected structure for valid inputs" do
    check all c <- integer(33..126),
              s <- integer(33..126) do
      input = List.to_string([c, s])
      result = CompressedPositionHelpers.convert_compressed_cs(input)

      if c == ?Z do
        assert is_map_key(result, :range)
        assert is_float(result.range)
      else
        assert is_map_key(result, :course)
        assert is_map_key(result, :speed)
        assert is_integer(result.course)
        assert is_float(result.speed)
      end
    end
  end
end
