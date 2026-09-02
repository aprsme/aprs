defmodule Aprs.NMEAHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.NMEAHelpers

  doctest NMEAHelpers

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
    test "parses RMC from any talker with speed in knots and an integer course" do
      sentence = "$GNRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W"

      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)
      assert_in_delta result.latitude, 48.1173, 0.000001
      assert_in_delta result.longitude, 11.516667, 0.000001
      assert result.speed == 22.4
      assert result.course == 84
      assert result.altitude == nil
      assert result.nmea_type == :rmc
      assert result.format == :nmea
    end

    test "normalizes a zero RMC course to due north and accepts a stripped prefix" do
      sentence = "QZRMC,214531,A,3242.4569,N,08527.2793,W,000,000,180226,,"

      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)
      assert result.speed == 0.0
      assert result.course == 360
      assert result.nmea_type == :rmc
    end

    test "rejects RMC with void status" do
      sentence = "$GPRMC,214531,V,3242.4569,N,08527.2793,W,000,209,180226,,*05"

      assert {:error, "RMC void status"} = NMEAHelpers.parse_nmea_sentence(sentence)
    end

    test "rejects malformed RMC speed and course instead of substituting zero" do
      assert {:error, "Invalid speed"} =
               NMEAHelpers.parse_nmea_sentence("$GPRMC,214531,A,3242.4569,N,08527.2793,W,abc,209,180226,,")

      assert {:error, "Invalid course"} =
               NMEAHelpers.parse_nmea_sentence("$GPRMC,214531,A,3242.4569,N,08527.2793,W,000,xyz,180226,,")
    end

    test "parses GGA position and converts altitude from metres to feet" do
      sentence = "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,"

      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)
      assert_in_delta result.latitude, 48.1173, 0.000001
      assert_in_delta result.longitude, 11.516667, 0.000001
      assert_in_delta result.altitude, 1789.370079, 0.000001
      assert result.speed == nil
      assert result.course == nil
      assert result.nmea_type == :gga
    end

    test "rejects GGA without a fix" do
      sentence = "$GNGGA,123519,4807.038,N,01131.000,E,0,00,9.9,0.0,M,0.0,M,,"

      assert {:error, "GGA no fix"} = NMEAHelpers.parse_nmea_sentence(sentence)
    end

    test "parses stripped-prefix GLL and checks its status" do
      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence("GPGLL,4916.45,N,12311.12,W,225444,A")
      assert_in_delta result.latitude, 49.274167, 0.000001
      assert_in_delta result.longitude, -123.185333, 0.000001
      assert result.speed == nil
      assert result.course == nil
      assert result.altitude == nil
      assert result.nmea_type == :gll

      assert {:error, "GLL void status"} =
               NMEAHelpers.parse_nmea_sentence("$GLGLL,4916.45,N,12311.12,W,225444,V*00")
    end

    test "parses VTG course and speed without inventing a position" do
      sentence = "$GAVTG,054.7,T,034.4,M,005.5,N,010.2,K*00"

      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)
      assert result.latitude == nil
      assert result.longitude == nil
      assert result.speed == 5.5
      assert result.course == 54
      assert result.altitude == nil
      assert result.nmea_type == :vtg
    end

    test "parses WPL coordinates and waypoint name" do
      sentence = "$BDWPL,4917.16,N,12310.64,W,003*65"

      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)
      assert_in_delta result.latitude, 49.286, 0.000001
      assert_in_delta result.longitude, -123.177333, 0.000001
      assert result.waypoint_name == "003"
      assert result.speed == nil
      assert result.course == nil
      assert result.altitude == nil
      assert result.nmea_type == :wpl
    end

    test "parses a complete Ultimeter packet into converted weather values" do
      sentence = "$ULTW000000BE02EB000027700000023A023A0025005800000000"

      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)
      assert result.latitude == nil
      assert result.longitude == nil
      assert result.speed == nil
      assert result.course == nil
      assert result.altitude == nil
      assert result.nmea_type == :ultimeter
      assert result.format == :nmea
      assert result.weather.wind_peak == 0.0
      assert_in_delta result.weather.wind_direction, 267.1875, 0.000001
      assert result.weather.outdoor_temperature == 74.7
      assert result.weather.rain_total == 0.0
      assert result.weather.barometer == 1009.6
      assert result.weather.outdoor_humidity == 57.0
      assert result.weather.indoor_humidity == 57.0
      assert result.weather.date == 37
      assert result.weather.time == 88
      assert result.weather.rain_today == 0.0
      assert result.weather.wind_average == 0.0
    end

    test "decodes signed Ultimeter temperatures" do
      payload =
        Enum.join(["----", "----", "FF9C", "----", "----", "FFF6", "----", "----", "----", "----", "----", "----"])

      assert {:ok, %{weather: weather}} = NMEAHelpers.parse_nmea_sentence("ULTW" <> payload)
      assert weather.outdoor_temperature == -10.0
      assert weather.indoor_temperature == -1.0
    end

    test "accepts the short Ultimeter example and treats dashed fields as missing" do
      assert {:ok, %{nmea_type: :ultimeter, weather: weather}} =
               NMEAHelpers.parse_nmea_sentence("$ULTW0000000002700000000000208A00000000000000000000")

      assert is_map(weather)

      assert {:ok, %{weather: missing}} =
               NMEAHelpers.parse_nmea_sentence("ULTW------------------------------------------------")

      assert Enum.all?(missing, fn {_field, value} -> value == nil end)
    end

    test "distinguishes unknown NMEA sentence types from non-NMEA input" do
      assert {:error, "Unsupported NMEA sentence type"} =
               NMEAHelpers.parse_nmea_sentence("$GPXYZ,1,2,3")

      assert {:error, "Unsupported NMEA sentence type"} =
               NMEAHelpers.parse_nmea_sentence("GNXYZ,1,2,3")

      assert {:error, "Not an NMEA sentence"} =
               NMEAHelpers.parse_nmea_sentence("not an nmea sentence")
    end

    test "rejects malformed sentences and non-string input" do
      assert {:error, "Invalid RMC sentence"} = NMEAHelpers.parse_nmea_sentence("$GPRMC,214531,A")
      assert {:error, "Not an NMEA sentence"} = NMEAHelpers.parse_nmea_sentence("")
      assert {:error, "Invalid NMEA input"} = NMEAHelpers.parse_nmea_sentence(nil)
      assert {:error, "Invalid NMEA input"} = NMEAHelpers.parse_nmea_sentence(123)
    end
  end

  describe "integration through Aprs.parse/1" do
    test "parses full WB4BYQ GPRMC packet with FAP-compatible output" do
      packet = "WB4BYQ-3>APT311,WIDE2-2,qAS,K4RY-1:$GPRMC,214531,A,3242.4569,N,08527.2793,W,000,209,180226,,*05"

      assert {:ok, result} = Aprs.parse(packet)
      assert result.type == "location"
      assert result.format == :nmea
      assert_in_delta result.latitude, 32.707615, 0.000001
      assert_in_delta result.longitude, -85.454655, 0.000001
      assert result.symboltable == "/"
      assert result.symbolcode == "/"
      assert result.posambiguity == 0
    end
  end
end
