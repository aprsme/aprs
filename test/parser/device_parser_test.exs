defmodule Aprs.DeviceParserTest do
  use ExUnit.Case, async: true

  alias Aprs.DeviceParser

  describe "extract_device_identifier/1" do
    test "extracts TOCALL from map with destination" do
      assert DeviceParser.extract_device_identifier(%{destination: "APRSWX"}) == "APRSWX"
      assert DeviceParser.extract_device_identifier(%{destination: "APRSWX123"}) == "APRSWX"
      assert DeviceParser.extract_device_identifier(%{destination: "APRS"}) == "APRS"
    end

    test "extracts TOCALL from map with data_type :mic_e and destination" do
      assert DeviceParser.extract_device_identifier(%{data_type: :mic_e, destination: "MICETX"}) == "MICETX"
      assert DeviceParser.extract_device_identifier(%{data_type: :mic_e, destination: "MICETX123"}) == "MICETX"
    end

    test "extracts device identifier from raw packet string with destination" do
      # Standard packet with destination
      assert DeviceParser.extract_device_identifier("CALLSIGN>APRSWX,TCPIP*:payload") == "APRSWX"
      assert DeviceParser.extract_device_identifier("CALL>DESTIN,TCPIP*:data") == "DESTIN"
      # Destination longer than 6 chars
      assert DeviceParser.extract_device_identifier("CALL>DESTIN123,TCPIP*:data") == "DESTIN"
      # No match for regex
      assert DeviceParser.extract_device_identifier("CALLSIGN-1:payload") == nil
      assert DeviceParser.extract_device_identifier("") == nil
    end

    test "returns nil for non-binary destination or non-matching input" do
      assert DeviceParser.extract_device_identifier(%{destination: 12_345}) == nil
      assert DeviceParser.extract_device_identifier(%{foo: "bar"}) == nil
      assert DeviceParser.extract_device_identifier(12_345) == nil
      assert DeviceParser.extract_device_identifier(nil) == nil
      assert DeviceParser.extract_device_identifier([]) == nil
      assert DeviceParser.extract_device_identifier(%{}) == nil
    end
  end
end
