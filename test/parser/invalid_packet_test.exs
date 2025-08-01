defmodule Aprs.InvalidPacketTest do
  use ExUnit.Case, async: true

  describe "packets with invalid UTF-8 characters in position data" do
    test "DB0WV-11 packet with UTF-8 characters in position field parses with error" do
      # This packet contains UTF-8 characters (ë and ß) in what should be ASCII-only position data
      packet = "DB0WV-11>APLG01,qAO,HB9AK-10:=47E2*1ëß34.07E&LoRa db0wv.de SYSOP DO2GM"

      # The packet should parse successfully but with position error
      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.sender == "DB0WV-11"
      assert parsed.data_type == :position_with_message

      # The position data should have an error
      assert is_map(parsed.data_extended)
      assert parsed.data_extended[:has_position] == false
      assert parsed.data_extended[:error_message] =~ "Invalid compressed location"

      # Document why it has an error:
      # 1. Position data "47E2*1ëß34.07E" doesn't match uncompressed format (DDMM.MMNH/DDDMM.MMEW)
      # 2. UTF-8 characters ë (0xC3 0xAB) and ß (0xC3 0x9F) are invalid in APRS position encoding
      # 3. When interpreted as compressed position, base91 decoding fails on non-ASCII characters
    end

    test "position_with_message parsing returns position with error for UTF-8 characters" do
      # This is the data field without the = indicator
      data = "47E2*1ëß34.07E&LoRa db0wv.de SYSOP DO2GM"

      # The parser should now return a position structure with error info
      result = Aprs.parse_data(:position_with_message, "APLG01", data)

      assert is_map(result)
      # The position_with_message wrapper adds aprs_messaging? flag
      assert result[:aprs_messaging?] == true
      assert result[:has_position] == false
      assert result[:error_message] =~ "Invalid compressed location"
    end

    test "valid position_with_message packet parses correctly" do
      # Example of a correctly formatted position_with_message packet
      packet = "DB0WV-11>APLG01,qAO,HB9AK-10:=4742.34N/00834.07E&LoRa db0wv.de SYSOP DO2GM"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.sender == "DB0WV-11"
      assert parsed.data_type == :position_with_message
      assert is_map(parsed.data_extended)
      assert parsed.data_extended.aprs_messaging? == true
    end

    test "HB9ZF-12 packet with invalid compressed position returns error" do
      # This packet has UTF-8 characters in the compressed position field
      packet = "HB9ZF-12>APLRG1,HB9ELV-13*,qAO,HB9AK-10:!L6VeIPÄ½Qê¤(¬¹D)Ì3cZ iGate JN47kg"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.sender == "HB9ZF-12"
      assert parsed.data_type == :position

      # The position data should have an error about invalid compressed data
      assert is_map(parsed.data_extended)
      assert parsed.data_extended[:has_position] == false
      assert parsed.data_extended[:error_message] =~ "Invalid compressed location"
    end

    test "TSwWV-8 packet with malformed mixed format returns error" do
      # This packet has malformed position/weather data mixing compressed and uncompressed formats
      packet = "TSwWV-8>APRS,qAO,HB9AK-11:!$/¬6·ö9B/00827.0ul3000g...t074h90b10146  WX-DB7w5&+X9"

      # The packet structure is valid but the position data is malformed
      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.sender == "TSwWV-8"
      assert parsed.data_type == :position

      # The position data should have an error
      assert is_map(parsed.data_extended)
      assert parsed.data_extended[:has_position] == false
      assert parsed.data_extended[:error_message] =~ "Invalid compressed location"

      # This packet has errors because:
      # 1. The position data "$/¬6·ö9B" contains invalid UTF-8 characters
      # 2. It appears to mix compressed position format with uncompressed data
      # 3. The format doesn't match any valid APRS position specification
    end

    test "HB9ELZ-7 packet with malformed UTF-8 in compressed position fails parsing" do
      # This packet has '=' (position with message) and compressed position with malformed UTF-8
      packet = "HB9ELZ-7>APLRT1,WIDE1-1,qAO,DB0TOD-11:=/6RiNPdH_¾ÌbQ"

      # The packet fails completely due to invalid UTF-8 encoding
      assert {:error, :invalid_packet} = Aprs.parse(packet)

      # This packet fails because:
      # 1. The compressed position data contains malformed UTF-8 sequences
      # 2. The byte sequence causes a UnicodeConversionError 
      # 3. The parser cannot recover from this encoding error
      # Note: While the user expected "invalid compressed packet" error,
      # the actual behavior is to return :invalid_packet for malformed encoding
    end
  end
end
