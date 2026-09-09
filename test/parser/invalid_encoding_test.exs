defmodule Aprs.InvalidEncodingTest do
  use ExUnit.Case, async: true

  doctest Aprs

  describe "parse/1 with invalid encoding" do
    test "handles APRS packet with UTF-8 characters in position field" do
      # This packet has UTF-8 characters ë and ß in the latitude field
      packet = "DB0WV-11>APLG01,qAO,HB9AK-10:=47E2*1ëß34.07E&LoRa db0wv.de SYSOP DO2GM"

      result = Aprs.parse(packet)

      # The parser should handle this gracefully
      assert {:ok, parsed} = result
      # A '=' packet whose body is neither a valid uncompressed nor a valid
      # compressed position reports the position error, not the position type
      # it failed to parse.
      assert parsed.data_type == :position_error

      # Check that the packet was parsed despite encoding issues
      assert parsed.sender == "DB0WV-11"
      assert parsed.destination == "APLG01"

      # The position data should have an error
      assert parsed.data_extended[:has_position] == false
      assert parsed.data_extended[:error_message] =~ "Invalid compressed location"
    end

    test "reports the same position error once the non-ASCII bytes are replaced" do
      # The packet above with every byte of ë and ß replaced by '?', which is
      # one byte per byte rather than one per character: still not a position.
      packet = "DB0WV-11>APLG01,qAO,HB9AK-10:=47E2*1????34.07E&LoRa db0wv.de SYSOP DO2GM"

      assert {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_type == :position_error
    end
  end
end
