defmodule Aprs.InvalidEncodingTest do
  use ExUnit.Case

  doctest Aprs

  describe "parse/1 with invalid encoding" do
    test "handles APRS packet with UTF-8 characters in position field" do
      # This packet has UTF-8 characters ë and ß in the latitude field
      packet = "DB0WV-11>APLG01,qAO,HB9AK-10:=47E2*1ëß34.07E&LoRa db0wv.de SYSOP DO2GM"

      result = Aprs.parse(packet)

      # The parser should handle this gracefully
      assert {:ok, parsed} = result
      # '=' indicator means position_with_message
      assert parsed.data_type == :position_with_message

      # Check that the packet was parsed despite encoding issues
      assert parsed.sender == "DB0WV-11"
      assert parsed.destination == "APLG01"

      # The position data should have an error
      assert parsed.data_extended[:has_position] == false
      assert parsed.data_extended[:error_message] =~ "Invalid compressed location"
    end

    test "demonstrates the encoding issue" do
      # Extract just the position data part
      position_data = "47E2*1ëß34.07E&LoRa db0wv.de SYSOP DO2GM"

      # Show that the latitude field has extra bytes due to UTF-8
      <<lat_attempt::binary-size(8), _rest::binary>> = position_data
      # Only gets part of ë
      assert lat_attempt == "47E2*1ë"

      # The actual byte size is different from character count
      actual_lat = "47E2*1ëß"
      # 8 characters
      assert String.length(actual_lat) == 8
      # 10 bytes due to UTF-8
      assert byte_size(actual_lat) == 10
    end

    test "shows ASCII replacement for non-ASCII characters" do
      # Test the regex replacement
      original = "47E2*1ëß34.07E&"
      # The regex replaces each byte of multi-byte UTF-8 characters
      replaced = String.replace(original, ~r/[^\x00-\x7F]/, "?")
      assert replaced == "47E2*1????34.07E&"

      # Now it should be 17 bytes
      assert byte_size(replaced) == 17
    end

    test "packet should parse after UTF-8 character replacement" do
      packet = "DB0WV-11>APLG01,qAO,HB9AK-10:=47E2*1ëß34.07E&LoRa db0wv.de SYSOP DO2GM"

      # Manually replace non-ASCII characters
      fixed_packet = String.replace(packet, ~r/[^\x00-\x7F]/, "?")
      assert fixed_packet == "DB0WV-11>APLG01,qAO,HB9AK-10:=47E2*1????34.07E&LoRa db0wv.de SYSOP DO2GM"

      # This should parse successfully
      result = Aprs.parse(fixed_packet)
      assert {:ok, parsed} = result
      # '=' indicator
      assert parsed.data_type == :position_with_message
    end
  end
end
