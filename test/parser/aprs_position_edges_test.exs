defmodule Aprs.PositionEdgesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Symbol table, four base-91 latitude bytes, four base-91 longitude bytes,
  # symbol code, cs pair and compression type byte.
  @compressed_frame "!/5L!!<*e7>7P["

  describe "compressed positions outside the coordinate range" do
    test "a latitude group past the south pole is a position error" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:!/{{{{AAAA>7P[")

      assert packet.data_type == :position_error
      assert packet.error_message == "Invalid compressed location: Invalid compressed latitude - out of range"
      refute packet.has_position
    end

    test "a longitude group past the antimeridian is a position error" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:!/AAAA{{{{>7P[")

      assert packet.data_type == :position_error
      assert packet.error_message == "Invalid compressed location: Invalid compressed longitude - out of range"
      refute packet.has_position
    end

    property "every base-91 group either decodes in range or is reported out of range" do
      check all latitude <- base91_group(),
                longitude <- base91_group() do
        assert {:ok, packet} = Aprs.parse("N0CALL>APRS:!/" <> latitude <> longitude <> ">7P[")

        case packet.data_type do
          :position ->
            assert packet.latitude >= -90 and packet.latitude <= 90
            assert packet.longitude >= -180 and packet.longitude <= 180
            assert packet.has_position

          :position_error ->
            assert packet.error_message =~ "out of range"
            refute packet.has_position
        end
      end
    end
  end

  describe "course and speed extension" do
    test "an unknown course and speed decodes as no course and no speed" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:!4903.50N/07201.75W>.../...Test")

      assert packet.course == 0
      assert packet.speed == nil
      assert packet.comment == "Test"
    end

    test "a blank course and speed decodes as no course and no speed" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:!4903.50N/07201.75W>   /   Test")

      assert packet.course == 0
      assert packet.speed == nil
      assert packet.comment == "Test"
    end

    test "a course and speed pair is decoded" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:!4903.50N/07201.75W>088/036Test")

      assert packet.course == 88
      assert packet.speed == 36.0
      assert packet.comment == "Test"
    end
  end

  describe "PHG inside a compressed comment" do
    test "PHG anywhere in the comment is extracted" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:" <> @compressed_frame <> "PHG5360 tail")

      assert packet.phg == "5360"
      assert packet.comment == "tail"
    end

    test "a PHG marker without four digits is skipped and the scan continues" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:" <> @compressed_frame <> "PHGab decoy PHG5360 tail")

      assert packet.phg == "5360"
      assert packet.comment == "PHGab decoy  tail"
    end

    test "a PHGR rate character and its slash are stripped with the PHG" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:" <> @compressed_frame <> "PHG5360A/ tail")

      assert packet.phg == "5360"
      assert packet.comment == "tail"
    end

    test "a numeric PHGR rate character is stripped too" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:" <> @compressed_frame <> "PHG53603/ tail")

      assert packet.phg == "5360"
      assert packet.comment == "tail"
    end
  end

  describe "SSID stripping on the Mic-E destination" do
    test "a numeric SSID is dropped before the destination is decoded" do
      assert {:ok, packet} = Aprs.parse("N0CALL-9>T7SXYZ-9,WIDE1-1:`(_fn\"Oj/")

      assert packet.data_type == :mic_e
      assert_in_delta packet.latitude, 47.649167, 0.000001
    end

    test "a trailing hyphen with no digits is not an SSID" do
      assert {:ok, packet} = Aprs.parse("N0CALL-9>T7SXYZ-,WIDE1-1:`(_fn\"Oj/")

      assert packet.destination == "T7SXYZ-"
      assert packet.data_type == :mic_e_error
      assert packet.latitude == nil
    end
  end

  describe "loose timestamped positions" do
    test "a short latitude and longitude still yields symbol and comment" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z4903.5N/07201.7W>comment here")

      assert packet.data_type == :timestamped_position_with_message
      assert packet.symbol_table_id == "/"
      assert packet.symbol_code == ">"
      assert packet.comment == "comment here"
    end

    test "a longitude that is not digits is rejected" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z4903.5N/notalongitudeatall")

      assert packet.data_type == :timestamped_position_error
      assert packet.error == "Invalid timestamped position format"
      assert packet.raw_data == "092345z4903.5N/notalongitudeatall"
    end

    test "a latitude with no minute fraction is rejected" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z4903.N/07201.75W>comment here")

      assert packet.data_type == :timestamped_position_error
      assert packet.raw_data == "092345z4903.N/07201.75W>comment here"
    end

    test "a latitude with no hemisphere is rejected" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z4903.5X/07201.75W>comment here")

      assert packet.data_type == :timestamped_position_error
      assert packet.raw_data == "092345z4903.5X/07201.75W>comment here"
    end
  end

  defp base91_group do
    gen all bytes <- list_of(integer(33..123), length: 4) do
      :binary.list_to_bin(bytes)
    end
  end
end
