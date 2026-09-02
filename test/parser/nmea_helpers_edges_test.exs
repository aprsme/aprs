defmodule Aprs.NMEAHelpersEdgesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.NMEAHelpers

  describe "sentence dispatch" do
    test "a dollar-prefixed string that is not a known sentence is unsupported" do
      assert NMEAHelpers.parse_nmea_sentence("$FOO") == {:error, "Unsupported NMEA sentence type"}
    end

    test "a string with no dollar prefix is still dispatched on its sentence type" do
      assert NMEAHelpers.parse_nmea_sentence("GPZZZ,1,2") == {:error, "Unsupported NMEA sentence type"}
    end
  end

  describe "GGA" do
    test "an empty altitude field leaves the altitude unknown" do
      assert {:ok, result} =
               NMEAHelpers.parse_nmea_sentence("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,,M,46.9,M,,*47")

      assert result.altitude == nil
      assert_in_delta result.latitude, 48.1173, 0.0001
      assert_in_delta result.longitude, 11.516667, 0.000001
    end

    test "an altitude in metres is reported in feet" do
      assert {:ok, result} =
               NMEAHelpers.parse_nmea_sentence("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47")

      assert_in_delta result.altitude, 1789.370079, 0.000001
    end

    test "a sentence with too few fields is invalid" do
      assert NMEAHelpers.parse_nmea_sentence("$GPGGA,123519,4807.038,N") == {:error, "Invalid GGA sentence"}
    end

    test "a zero-padded fix quality still means no fix" do
      assert NMEAHelpers.parse_nmea_sentence("$GPGGA,123519,4807.038,N,01131.000,E,00,08,0.9,545.4,M,46.9,M,,*47") ==
               {:error, "GGA no fix"}
    end

    test "a non-numeric fix quality is rejected" do
      assert NMEAHelpers.parse_nmea_sentence("$GPGGA,123519,4807.038,N,01131.000,E,x,08,0.9,545.4,M,46.9,M,,*47") ==
               {:error, "Invalid GGA fix quality"}
    end
  end

  describe "malformed sentences" do
    test "a short GLL sentence is invalid" do
      assert NMEAHelpers.parse_nmea_sentence("$GPGLL,4916.45,N") == {:error, "Invalid GLL sentence"}
    end

    test "a short VTG sentence is invalid" do
      assert NMEAHelpers.parse_nmea_sentence("$GPVTG,054.7,T") == {:error, "Invalid VTG sentence"}
    end

    test "a short WPL sentence is invalid" do
      assert NMEAHelpers.parse_nmea_sentence("$GPWPL,4917.24,N") == {:error, "Invalid WPL sentence"}
    end
  end

  describe "RMC" do
    test "empty speed and course fields leave both unknown" do
      assert {:ok, result} =
               NMEAHelpers.parse_nmea_sentence("$GPRMC,123519,A,4807.038,N,01131.000,E,,,230394,003.1,W*6A")

      assert result.speed == nil
      assert result.course == nil
      assert_in_delta result.latitude, 48.1173, 0.0001
    end

    test "a zero course is reported as due north" do
      assert {:ok, result} =
               NMEAHelpers.parse_nmea_sentence("$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,000.0,230394,003.1,W*6A")

      assert result.course == 360
      assert result.speed == 22.4
    end

    property "a well formed RMC sentence decodes hemispheres, speed and course" do
      check all degrees_lat <- integer(0..89),
                minutes_lat <- integer(0..5999),
                degrees_lon <- integer(0..179),
                minutes_lon <- integer(0..5999),
                lat_dir <- member_of(["N", "S"]),
                lon_dir <- member_of(["E", "W"]),
                speed <- integer(0..9999),
                course <- integer(0..360) do
        latitude = pad(degrees_lat, 2) <> minutes(minutes_lat)
        longitude = pad(degrees_lon, 3) <> minutes(minutes_lon)
        speed_field = pad(speed, 3) <> ".0"
        course_field = pad(course, 3) <> ".0"

        sentence =
          Enum.join(
            ["$GPRMC,123519,A", latitude, lat_dir, longitude, lon_dir, speed_field, course_field, "230394,003.1,W"],
            ","
          )

        assert {:ok, result} = NMEAHelpers.parse_nmea_sentence(sentence)

        assert result.latitude >= -90 and result.latitude <= 90
        assert result.longitude >= -180 and result.longitude <= 180
        assert (lat_dir == "N" and result.latitude >= 0) or (lat_dir == "S" and result.latitude <= 0)
        assert (lon_dir == "E" and result.longitude >= 0) or (lon_dir == "W" and result.longitude <= 0)
        assert result.speed == speed * 1.0
        assert result.course in 1..360
      end
    end
  end

  describe "Ultimeter payloads" do
    test "a full payload decodes every field" do
      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence("$ULTW" <> String.duplicate("0", 48))

      assert result.nmea_type == :ultimeter
      assert result.weather.wind_average == 0.0
      assert result.weather.rain_today == 0.0
    end

    test "a payload without the wind average field pads it out as missing" do
      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence("$ULTW" <> String.duplicate("0", 44))

      assert result.weather.rain_today == 0.0
      assert result.weather.wind_average == nil
    end

    test "a payload without rain today or wind average pads both out as missing" do
      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence("$ULTW" <> String.duplicate("0", 40))

      assert result.weather.rain_today == nil
      assert result.weather.wind_average == nil
      assert result.weather.barometer == 0.0
    end

    test "a payload of an unsupported length is rejected" do
      assert NMEAHelpers.parse_nmea_sentence("$ULTW" <> String.duplicate("0", 42)) ==
               {:error, "Invalid Ultimeter sentence"}
    end

    test "a field that is not hexadecimal decodes as missing" do
      assert {:ok, result} = NMEAHelpers.parse_nmea_sentence("$ULTW" <> "ZZZZ" <> String.duplicate("0", 44))

      assert result.weather.wind_peak == nil
      assert result.weather.wind_direction == 0.0
    end

    test "a short Ultimeter payload parses as a packet" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:$ULTW" <> String.duplicate("0", 40))

      assert packet.data_type == :raw_gps_ultimeter
      assert packet.nmea_type == :ultimeter
      assert packet.weather.wind_average == nil
    end
  end

  defp pad(value, width), do: value |> Integer.to_string() |> String.pad_leading(width, "0")

  defp minutes(hundredths) do
    pad(div(hundredths, 100), 2) <> "." <> pad(rem(hundredths, 100), 2)
  end
end
