defmodule Aprs.CompressedPositionResolutionTest do
  use ExUnit.Case, async: true

  describe "compressed position resolution parsing" do
    # Packets must have enough data after the type indicator for the uncompressed
    # format check to fail and fall through to compressed parsing (≥19 chars).
    # Format after stripping '!': sym_table(1) + lat(4) + lon(4) + sym(1) + cs(2) + type(1) + comment
    test "parses position with no ambiguity (resolution 0)" do
      # '!' = 0x21, offset=0, bits 2-4 = 0 → resolution 0
      packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s! comment"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_extended[:position_ambiguity] == 0
      assert parsed.data_extended[:compression_info][:position_resolution] == 0
      assert parsed.data_extended[:compression_info][:gps_fix_type] == :other
      assert parsed.data_extended[:compression_info][:old_gps_data] == false
    end

    test "parses position with 0.1 minute ambiguity (resolution 1)" do
      # '%' = 0x25, offset=4 (0b000100), bits 2-4 = 001 → resolution 1
      packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s% comment"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_extended[:position_ambiguity] == 1
      assert parsed.data_extended[:compression_info][:position_resolution] == 1
    end

    test "parses position with 1 minute ambiguity (resolution 2)" do
      # ')' = 0x29, offset=8 (0b001000), bits 2-4 = 010 → resolution 2
      packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s) comment"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_extended[:position_ambiguity] == 2
      assert parsed.data_extended[:compression_info][:position_resolution] == 2
    end

    test "parses position with 10 minute ambiguity (resolution 3)" do
      # '-' = 0x2D, offset=12 (0b001100), bits 2-4 = 011 → resolution 3
      packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s- comment"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_extended[:position_ambiguity] == 3
      assert parsed.data_extended[:compression_info][:position_resolution] == 3
    end

    test "parses position with 1 degree ambiguity (resolution 4)" do
      # '1' = 0x31, offset=16 (0b010000), bits 2-4 = 100 → resolution 4
      packet = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s1 comment"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_extended[:position_ambiguity] == 4
      assert parsed.data_extended[:compression_info][:position_resolution] == 4
    end

    test "parses GPS fix type from compression byte" do
      # Type 0: Other source ('!' = 0x21, offset=0, bits 0-1 = 00)
      packet1 = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s! comment"
      {:ok, parsed1} = Aprs.parse(packet1)
      assert parsed1.data_extended[:compression_info][:gps_fix_type] == :other

      # Type 1: GLL/GGA ('"' = 0x22, offset=1, bits 0-1 = 01)
      packet2 = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s\" comment"
      {:ok, parsed2} = Aprs.parse(packet2)
      assert parsed2.data_extended[:compression_info][:gps_fix_type] == :gll_gga

      # Type 2: RMC ('#' = 0x23, offset=2, bits 0-1 = 10)
      packet3 = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s# comment"
      {:ok, parsed3} = Aprs.parse(packet3)
      assert parsed3.data_extended[:compression_info][:gps_fix_type] == :rmc
    end

    test "parses old GPS data flag" do
      # Not old data ('!' = 0x21, bit 5 = 0)
      packet1 = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> s! comment"
      {:ok, parsed1} = Aprs.parse(packet1)
      assert parsed1.data_extended[:compression_info][:old_gps_data] == false

      # Old data ('A' = 0x41, offset=32 = 0b100000, bit 5 = 1)
      packet2 = "N0CALL>APRS,TCPIP*:!/5L!!<*e7> sA comment"
      {:ok, parsed2} = Aprs.parse(packet2)
      assert parsed2.data_extended[:compression_info][:old_gps_data] == true
    end

    test "compressed position with L overlay consumes cs and type bytes" do
      # APRS compressed format always has 13 bytes: sym(1)+lat(4)+lon(4)+sym(1)+cs(2)+type(1)
      packet = "N0CALL>APRS,TCPIP*:!L5L!!<*e7& comment"
      {:ok, parsed} = Aprs.parse(packet)

      # All compressed formats consume cs and compression_type bytes
      assert parsed.data_extended[:compressed?] == true
      assert parsed.data_extended[:compression_type]
    end
  end

  describe "compression type byte calculations" do
    test "correctly decodes compression type examples" do
      # Test specific byte values from APRS spec

      # Space (0x20) should give all zeros
      assert Aprs.CompressedPositionHelpers.parse_compression_type(" ") == %{
               gps_fix_type: :other,
               position_resolution: 0,
               old_gps_data: false,
               aprs_messaging: 0
             }

      # '!' (0x21) = offset 0
      assert Aprs.CompressedPositionHelpers.parse_compression_type("!") == %{
               gps_fix_type: :other,
               position_resolution: 0,
               old_gps_data: false,
               aprs_messaging: 0
             }

      # Complex example: 'S' (0x53 = 83)
      # offset = 83 - 33 = 50 = 0b110010
      # bits 0-1: 10 = RMC
      # bits 2-4: 100 = resolution 4  
      # bit 5: 1 = old data
      assert Aprs.CompressedPositionHelpers.parse_compression_type("S") == %{
               gps_fix_type: :rmc,
               position_resolution: 4,
               old_gps_data: true,
               aprs_messaging: 0
             }
    end
  end
end
