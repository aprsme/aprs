defmodule Aprs.NMEAHelpersTest do
  use ExUnit.Case

  alias Aprs.NMEAHelpers

  describe "parse_nmea_coordinate/2" do
        test "parses valid latitude coordinates" do
      # Test North latitude
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", "N") == {:ok, 40.421234}
      assert NMEAHelpers.parse_nmea_coordinate("0000.0000", "N") == {:ok, 0.0}
      assert NMEAHelpers.parse_nmea_coordinate("9000.0000", "N") == {:ok, 90.0}

      # Test South latitude
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", "S") == {:ok, -40.421234}
      assert NMEAHelpers.parse_nmea_coordinate("0000.0000", "S") == {:ok, 0.0}
      assert NMEAHelpers.parse_nmea_coordinate("9000.0000", "S") == {:ok, -90.0}
    end

        test "parses valid longitude coordinates" do
      # Test East longitude
      assert NMEAHelpers.parse_nmea_coordinate("07415.6789", "E") == {:ok, 74.156789}
      assert NMEAHelpers.parse_nmea_coordinate("00000.0000", "E") == {:ok, 0.0}
      assert NMEAHelpers.parse_nmea_coordinate("18000.0000", "E") == {:ok, 180.0}

      # Test West longitude
      assert NMEAHelpers.parse_nmea_coordinate("07415.6789", "W") == {:ok, -74.156789}
      assert NMEAHelpers.parse_nmea_coordinate("00000.0000", "W") == {:ok, 0.0}
      assert NMEAHelpers.parse_nmea_coordinate("18000.0000", "W") == {:ok, -180.0}
    end

    test "handles decimal values correctly" do
      # Test various decimal precisions
      assert NMEAHelpers.parse_nmea_coordinate("1234.5678", "N") == {:ok, 12.345678}
      assert NMEAHelpers.parse_nmea_coordinate("1234.5", "N") == {:ok, 12.345}
      assert NMEAHelpers.parse_nmea_coordinate("1234", "N") == {:ok, 12.34}
    end

        test "handles edge cases" do
      # Test boundary values
      assert NMEAHelpers.parse_nmea_coordinate("5959.9999", "N") == {:ok, 59.599999}
      assert NMEAHelpers.parse_nmea_coordinate("17959.9999", "E") == {:ok, 179.599999}

      # Test zero values
      assert NMEAHelpers.parse_nmea_coordinate("0", "N") == {:ok, 0.0}
      assert NMEAHelpers.parse_nmea_coordinate("0.0", "S") == {:ok, 0.0}
    end

        test "returns error for invalid coordinate values" do
      # Test non-numeric values
      assert NMEAHelpers.parse_nmea_coordinate("invalid", "N") == {:error, "Invalid coordinate value"}
      assert NMEAHelpers.parse_nmea_coordinate("abc123", "S") == {:error, "Invalid coordinate value"}

      # Test empty strings
      assert NMEAHelpers.parse_nmea_coordinate("", "W") == {:error, "Invalid coordinate value"}
    end

    test "returns error for invalid direction" do
      # Test invalid direction values
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", "X") == {:error, "Invalid coordinate direction"}
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", "A") == {:error, "Invalid coordinate direction"}
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", "Z") == {:error, "Invalid coordinate direction"}
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", "1") == {:error, "Invalid coordinate direction"}
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", "!") == {:error, "Invalid coordinate direction"}
    end

    test "returns error for invalid input types" do
      # Test non-binary inputs
      assert NMEAHelpers.parse_nmea_coordinate(123, "N") == {:error, "Invalid coordinate format"}
      assert NMEAHelpers.parse_nmea_coordinate(45.67, "S") == {:error, "Invalid coordinate format"}
      assert NMEAHelpers.parse_nmea_coordinate(:atom, "E") == {:error, "Invalid coordinate format"}
      assert NMEAHelpers.parse_nmea_coordinate(nil, "W") == {:error, "Invalid coordinate format"}

      # Test non-binary direction
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", :north) == {:error, "Invalid coordinate format"}
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", 123) == {:error, "Invalid coordinate format"}
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", nil) == {:error, "Invalid coordinate format"}
    end

    test "handles mixed invalid inputs" do
      # Test both invalid coordinate and direction
      assert NMEAHelpers.parse_nmea_coordinate("invalid", "X") == {:error, "Invalid coordinate value"}
      assert NMEAHelpers.parse_nmea_coordinate(123, :north) == {:error, "Invalid coordinate format"}
    end
  end

  describe "parse_nmea_sentence/1" do
    test "returns error for any input" do
      # Test various inputs - all should return the same error
      assert NMEAHelpers.parse_nmea_sentence("$GPGGA,123456,4042.1234,N,07415.6789,W,1,8,1.2,100,M,0,M,,*6A") ==
               {:error, "NMEA parsing not implemented"}

      assert NMEAHelpers.parse_nmea_sentence("$GPRMC,123456,A,4042.1234,N,07415.6789,W,10.5,45.2,010120,15.5,E*6A") ==
               {:error, "NMEA parsing not implemented"}

      assert NMEAHelpers.parse_nmea_sentence("") ==
               {:error, "NMEA parsing not implemented"}

      assert NMEAHelpers.parse_nmea_sentence(nil) ==
               {:error, "NMEA parsing not implemented"}

      assert NMEAHelpers.parse_nmea_sentence(123) ==
               {:error, "NMEA parsing not implemented"}

      assert NMEAHelpers.parse_nmea_sentence(:atom) ==
               {:error, "NMEA parsing not implemented"}
    end
  end

  describe "integration scenarios" do
    test "typical GPS coordinate parsing" do
      # Simulate typical GPS coordinates from a weather station
      lat_coord = "4042.1234"
      lon_coord = "07415.6789"

      {:ok, latitude} = NMEAHelpers.parse_nmea_coordinate(lat_coord, "N")
      {:ok, longitude} = NMEAHelpers.parse_nmea_coordinate(lon_coord, "W")

      assert_in_delta latitude, 40.421234, 0.0001
      assert_in_delta longitude, -74.156789, 0.0001
    end

    test "southern hemisphere coordinates" do
      # Test coordinates in the southern hemisphere
      {:ok, lat} = NMEAHelpers.parse_nmea_coordinate("3354.5678", "S")
      {:ok, lon} = NMEAHelpers.parse_nmea_coordinate("15112.3456", "E")

      assert_in_delta lat, -33.545678, 0.0001
      assert_in_delta lon, 151.123456, 0.0001
    end

    test "equator and prime meridian" do
      # Test coordinates at the equator and prime meridian
      {:ok, equator_lat} = NMEAHelpers.parse_nmea_coordinate("0000.0000", "N")
      {:ok, prime_meridian_lon} = NMEAHelpers.parse_nmea_coordinate("00000.0000", "E")

      assert_in_delta equator_lat, 0.0, 0.0001
      assert_in_delta prime_meridian_lon, 0.0, 0.0001
    end

    test "extreme coordinates" do
      # Test extreme coordinate values
      {:ok, max_lat} = NMEAHelpers.parse_nmea_coordinate("9000.0000", "N")
      {:ok, min_lat} = NMEAHelpers.parse_nmea_coordinate("9000.0000", "S")
      {:ok, max_lon} = NMEAHelpers.parse_nmea_coordinate("18000.0000", "E")
      {:ok, min_lon} = NMEAHelpers.parse_nmea_coordinate("18000.0000", "W")

      assert_in_delta max_lat, 90.0, 0.0001
      assert_in_delta min_lat, -90.0, 0.0001
      assert_in_delta max_lon, 180.0, 0.0001
      assert_in_delta min_lon, -180.0, 0.0001
    end
  end

  describe "error handling edge cases" do
    test "handles very long coordinate strings" do
      long_coord = "4042.1234567890123456789012345678901234567890"
      assert NMEAHelpers.parse_nmea_coordinate(long_coord, "N") == {:ok, 40.421234567890124}
    end

    test "handles coordinate strings with leading/trailing spaces" do
      # Note: The function doesn't trim spaces, so these should work as-is
      assert NMEAHelpers.parse_nmea_coordinate(" 4042.1234", "N") == {:error, "Invalid coordinate value"}
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234 ", "N") == {:ok, 40.421234}
    end

    test "handles direction strings with leading/trailing spaces" do
      # Note: The function doesn't trim spaces, so these should fail
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", " N") == {:error, "Invalid coordinate direction"}
      assert NMEAHelpers.parse_nmea_coordinate("4042.1234", "N ") == {:error, "Invalid coordinate direction"}
    end
  end
end
