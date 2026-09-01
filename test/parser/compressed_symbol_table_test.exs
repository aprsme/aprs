defmodule Aprs.CompressedSymbolTableTest do
  use ExUnit.Case, async: true

  describe "compressed position with leading symbol table" do
    test "HB9ZF-12 packet with symbol table 'L' before compressed position" do
      packet = "HB9ZF-12>APLRG1,HB9ELV-13*,qAO,HB9AK-10:!L6VeIPd9U& ik��6��Ye JN47kg"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.sender == "HB9ZF-12"
      assert parsed.data_type == :position

      # Check the position data
      data = parsed.data_extended
      assert data.compressed? == true
      assert data.symbol_table_id == "L"
      assert data.symbol_code == "&"
      assert data.position_ambiguity == 0
      assert data.compression_info == %{gps_fix: :old, nmea_source: :gll, origin: :software}

      # Verify coordinates are correct
      assert_in_delta data.latitude, 47.288, 0.001
      assert_in_delta data.longitude, 8.881, 0.001

      # The comment should preserve the binary data
      assert data.comment =~ "JN47kg"
    end

    test "correctly distinguishes between compressed formats" do
      # Standard compressed with "/" prefix — needs ≥19 chars after type indicator
      packet1 = "TEST>APRS:!/5L!!<*e7> s! comment"
      {:ok, parsed1} = Aprs.parse(packet1)
      assert parsed1.data_extended.symbol_table_id == "/"
      assert parsed1.data_extended.compressed? == true
      assert parsed1.data_extended.position_ambiguity == 0

      assert parsed1.data_extended.compression_info == %{
               gps_fix: :old,
               nmea_source: :other,
               origin: :compressed
             }

      # Compressed with alternate symbol table
      packet2 = "TEST>APRS:!\\5L!!<*e7& sT comment"
      {:ok, parsed2} = Aprs.parse(packet2)
      assert parsed2.data_extended.symbol_table_id == "\\"
      assert parsed2.data_extended.symbol_code == "&"
      assert parsed2.data_extended.compressed? == true
      assert parsed2.data_extended.position_ambiguity == 0

      assert parsed2.data_extended.compression_info == %{
               gps_fix: :current,
               nmea_source: :gga,
               origin: :tbd
             }
    end
  end
end
