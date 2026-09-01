defmodule Aprs.CompressedPositionResolutionTest do
  use ExUnit.Case, async: true

  describe "compressed position metadata" do
    test "parses the APRS101 course and speed example at full precision" do
      packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7>7P[ comment"
      {:ok, parsed} = Aprs.parse(packet)
      data = parsed.data_extended

      assert data[:position_ambiguity] == 0

      assert data[:compression_info] == %{
               gps_fix: :current,
               nmea_source: :rmc,
               origin: :software
             }

      assert_in_delta data[:latitude], 49.5, 1.0e-6
      assert_in_delta data[:longitude], -72.75, 1.0e-5
      assert data[:course] == 88
      assert_in_delta data[:speed], 36.2, 0.1
    end

    test "compression source and origin bits do not create position ambiguity" do
      cases = [
        {"!", %{gps_fix: :old, nmea_source: :other, origin: :compressed}},
        {"%", %{gps_fix: :old, nmea_source: :other, origin: :kpc3}},
        {")", %{gps_fix: :old, nmea_source: :gll, origin: :compressed}},
        {"-", %{gps_fix: :old, nmea_source: :gll, origin: :kpc3}},
        {"Y", %{gps_fix: :current, nmea_source: :rmc, origin: :compressed}}
      ]

      for {type, expected_info} <- cases do
        packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7>7P#{type} comment"
        {:ok, parsed} = Aprs.parse(packet)
        data = parsed.data_extended

        assert data[:position_ambiguity] == 0
        assert data[:compression_info] == expected_info
        assert_in_delta data[:latitude], 49.5, 1.0e-6
        assert_in_delta data[:longitude], -72.75, 1.0e-5
        assert data[:course] == 88
        assert_in_delta data[:speed], 36.2, 0.1
      end
    end

    test "decodes a GGA cs pair as altitude" do
      packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7>S]1 comment"
      {:ok, parsed} = Aprs.parse(packet)
      data = parsed.data_extended

      assert data[:position_ambiguity] == 0

      assert data[:compression_info] == %{
               gps_fix: :old,
               nmea_source: :gga,
               origin: :compressed
             }

      assert_in_delta data[:latitude], 49.5, 1.0e-6
      assert_in_delta data[:longitude], -72.75, 1.0e-5
      assert_in_delta data[:altitude], 1.002 ** 4610, 1.0e-9
      refute Map.has_key?(data, :course)
      refute Map.has_key?(data, :speed)
    end

    test "decodes T according to its actual bit layout" do
      packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7>S]T comment"
      {:ok, parsed} = Aprs.parse(packet)
      data = parsed.data_extended

      assert data[:position_ambiguity] == 0

      assert data[:compression_info] == %{
               gps_fix: :current,
               nmea_source: :gga,
               origin: :tbd
             }

      assert_in_delta data[:altitude], 1.002 ** 4610, 1.0e-9
    end

    test "compressed position with L overlay consumes cs and type bytes" do
      packet = "N0CALL>APRS,TCPIP*:!L5L!!<*e7&7P! comment"
      {:ok, parsed} = Aprs.parse(packet)
      data = parsed.data_extended

      assert data[:compressed?] == true
      assert data[:position_ambiguity] == 0

      assert data[:compression_info] == %{
               gps_fix: :old,
               nmea_source: :other,
               origin: :compressed
             }

      assert data[:course] == 88
      assert_in_delta data[:speed], 36.2, 0.1
    end
  end
end
