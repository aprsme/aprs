defmodule Aprs.NMEAHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.NMEAHelpers

  describe "parse_nmea_coordinate/2" do
    test "parses valid latitude coordinates with correct DD+MM/60 conversion" do
      # 4903.50 = 49 degrees, 03.50 minutes = 49 + 3.50/60 = 49.058333...
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("4903.50", "N")
      assert_in_delta result, 49.058333, 0.000001

      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("4903.50", "S")
      assert_in_delta result, -49.058333, 0.000001
    end

    test "parses valid longitude coordinates with correct DD+MM/60 conversion" do
      # 7201.75 = 72 degrees, 01.75 minutes = 72 + 1.75/60 = 72.029167
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("7201.75", "E")
      assert_in_delta result, 72.029167, 0.000001

      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("7201.75", "W")
      assert_in_delta result, -72.029167, 0.000001
    end

    test "parses the target GPRMC packet coordinates" do
      # 3242.4569 = 32 degrees, 42.4569 minutes = 32 + 42.4569/60 = 32.707615
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("3242.4569", "N")
      assert_in_delta result, 32.707615, 0.000001

      # 08527.2793 = 85 degrees, 27.2793 minutes = 85 + 27.2793/60 = 85.454655
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("08527.2793", "W")
      assert_in_delta result, -85.454655, 0.000001
    end

    test "handles various coordinate formats" do
      # 3339.3 = 33 degrees, 39.3 minutes = 33 + 39.3/60 = 33.655
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("3339.3", "N")
      assert_in_delta result, 33.655, 0.001

      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("3339.3", "S")
      assert_in_delta result, -33.655, 0.001

      # 11815.0 = 118 degrees, 15.0 minutes = 118 + 15.0/60 = 118.25
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("11815.0", "E")
      assert_in_delta result, 118.25, 0.001

      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("11815.0", "W")
      assert_in_delta result, -118.25, 0.001
    end

    test "handles zero coordinates" do
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("0.0", "N")
      assert result == 0.0
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("0.0", "E")
      assert result == 0.0
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("0.0", "S")
      assert result == 0.0
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("0.0", "W")
      assert result == 0.0
    end

    test "handles coordinate with high precision" do
      # 4903.50 = 49 + 3.50/60 = 49.058333
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("4903.50", "N")
      assert_in_delta result, 49.058333, 0.000001

      # 4903.52 = 49 + 3.52/60 = 49.058667
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("4903.52", "N")
      assert_in_delta result, 49.058667, 0.000001
    end

    test "returns error for invalid coordinate values" do
      assert {:error, "Invalid coordinate value"} = NMEAHelpers.parse_nmea_coordinate("invalid", "N")
      assert {:error, "Invalid coordinate value"} = NMEAHelpers.parse_nmea_coordinate("abc.def", "N")
      assert {:error, "Invalid coordinate value"} = NMEAHelpers.parse_nmea_coordinate("", "N")
    end

    test "returns error for invalid directions" do
      assert {:error, "Invalid coordinate direction"} = NMEAHelpers.parse_nmea_coordinate("4903.50", "X")
      assert {:error, "Invalid coordinate direction"} = NMEAHelpers.parse_nmea_coordinate("4903.50", "Z")
      assert {:error, "Invalid coordinate direction"} = NMEAHelpers.parse_nmea_coordinate("4903.50", "")
      assert {:error, "Invalid coordinate direction"} = NMEAHelpers.parse_nmea_coordinate("4903.50", "north")
    end

    test "handles non-binary inputs" do
      assert {:error, "Invalid coordinate format"} = NMEAHelpers.parse_nmea_coordinate(123, "N")
      assert {:error, "Invalid coordinate format"} = NMEAHelpers.parse_nmea_coordinate("4903.50", 123)
      assert {:error, "Invalid coordinate format"} = NMEAHelpers.parse_nmea_coordinate(nil, "N")
      assert {:error, "Invalid coordinate format"} = NMEAHelpers.parse_nmea_coordinate("4903.50", nil)
    end

    test "handles edge case directions" do
      assert {:ok, coord} = NMEAHelpers.parse_nmea_coordinate("4903.50", "N")
      assert coord > 0

      assert {:ok, coord} = NMEAHelpers.parse_nmea_coordinate("4903.50", "S")
      assert coord < 0

      assert {:ok, coord} = NMEAHelpers.parse_nmea_coordinate("4903.50", "E")
      assert coord > 0

      assert {:ok, coord} = NMEAHelpers.parse_nmea_coordinate("4903.50", "W")
      assert coord < 0
    end

    test "handles coordinates with no decimal point" do
      # 4900 = 49 degrees, 00 minutes = 49.0
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("4900", "N")
      assert_in_delta result, 49.0, 0.001

      # 1000 = 10 degrees, 00 minutes = 10.0
      assert {:ok, result} = NMEAHelpers.parse_nmea_coordinate("1000", "N")
      assert_in_delta result, 10.0, 0.001
    end

    property "coordinate parsing produces correct signs" do
      check all coord_str <- StreamData.string(:ascii, min_length: 1, max_length: 10),
                direction <- StreamData.member_of(["N", "S", "E", "W"]) do
        if String.match?(coord_str, ~r/^\d+\.\d+$/) do
          case NMEAHelpers.parse_nmea_coordinate(coord_str, direction) do
            {:ok, result} ->
              case direction do
                "N" -> assert result >= 0
                "E" -> assert result >= 0
                "S" -> assert result <= 0
                "W" -> assert result <= 0
              end

            {:error, _} ->
              :ok
          end
        end
      end
    end
  end

  describe "parse_nmea_sentence/1" do
    test "parses valid $GPRMC sentence" do
      sentence = "$GPRMC,214531,A,3242.4569,N,08527.2793,W,000,209,180226,,*05"

      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)
      assert_in_delta result.latitude, 32.707615, 0.000001
      assert_in_delta result.longitude, -85.454655, 0.000001
      assert result.speed == 0
      assert result.course == 209
      assert result.format == "nmea"
    end

    test "parses $GPRMC with non-zero speed" do
      sentence = "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,,*23"

      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)
      assert_in_delta result.latitude, 48.1173, 0.001
      assert_in_delta result.longitude, 11.516667, 0.001
      assert result.speed == 22
      assert result.course == 84
      assert result.format == "nmea"
    end

    test "rejects $GPRMC with void status" do
      sentence = "$GPRMC,214531,V,3242.4569,N,08527.2793,W,000,209,180226,,*05"

      assert {:error, "GPRMC void status"} = NMEAHelpers.parse_nmea_sentence(sentence)
    end

    test "rejects non-GPRMC sentences" do
      assert {:error, "Unsupported NMEA sentence type"} =
               NMEAHelpers.parse_nmea_sentence("$GPGGA,123456,4903.50,N,07201.75,W,1,04,2.3,545.4,M,46.9,M,,*47")
    end

    test "rejects sentences with too few fields" do
      assert {:error, _reason} = NMEAHelpers.parse_nmea_sentence("$GPRMC,214531,A")
    end

    test "rejects non-string input" do
      assert {:error, _reason} = NMEAHelpers.parse_nmea_sentence(nil)
      assert {:error, _reason} = NMEAHelpers.parse_nmea_sentence(123)
    end

    test "rejects empty string" do
      assert {:error, _reason} = NMEAHelpers.parse_nmea_sentence("")
    end

    test "rejects non-NMEA string" do
      assert {:error, _reason} = NMEAHelpers.parse_nmea_sentence("not an nmea sentence")
    end
  end

  describe "integration through Aprs.parse/1" do
    test "parses full WB4BYQ GPRMC packet with FAP-compatible output" do
      packet = "WB4BYQ-3>APT311,WIDE2-2,qAS,K4RY-1:$GPRMC,214531,A,3242.4569,N,08527.2793,W,000,209,180226,,*05"

      assert {:ok, result} = Aprs.parse(packet)
      assert result.type == "location"
      assert result.format == "nmea"
      assert_in_delta result.latitude, 32.707615, 0.000001
      assert_in_delta result.longitude, -85.454655, 0.000001
      assert result.symboltable == "/"
      assert result.symbolcode == "/"
      assert result.posambiguity == 0
    end
  end
end
