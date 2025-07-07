defmodule Aprs.DeviceParserTest do
  use ExUnit.Case

  alias Aprs.DeviceParser

  describe "extract_device_identifier/1" do
    test "standard TOCALL extraction" do
      assert DeviceParser.extract_device_identifier(%{destination: "APRSWX"}) == "APRSWX"
      assert DeviceParser.extract_device_identifier(%{destination: "APK123"}) == "APK123"
      assert DeviceParser.extract_device_identifier(%{destination: "SHORT"}) == "SHORT"
    end

    test "Mic-E TOCALL decoding (known prefix)" do
      # T5TYR4: Kenwood TH-D74 special case
      assert DeviceParser.decode_mic_e_tocall("T5TYR4") == "APK004"
      # T5TYR2: Kenwood TH-D74 special case
      assert DeviceParser.decode_mic_e_tocall("T5TYR2") == "APK002"
      # T2T000: T2T -> APN, 0,0,0 => 0
      assert DeviceParser.decode_mic_e_tocall("T2T000") == "APN000"
      # S6V999: S6V -> APW, 9,9,9 => 999
      assert DeviceParser.decode_mic_e_tocall("S6V999") == "APW999"
    end

    test "Mic-E TOCALL decoding (unknown prefix)" do
      # Unknown prefix falls back to destination
      assert DeviceParser.decode_mic_e_tocall("ZZZ123") == "ZZZ123"
    end

    test "legacy Mic-E device identification from comment" do
      # Kenwood TH-D74: prefix ">", suffix "^"
      packet = %{data_type: :mic_e, destination: "T5TYR2", data_extended: %{comment: ">random^"}}
      assert DeviceParser.extract_device_identifier(packet) == "APK004"

      # Kenwood TH-D72: prefix ">", suffix "="
      packet2 = %{data_type: :mic_e, destination: "T5TYR2", data_extended: %{comment: ">foo="}}
      assert DeviceParser.extract_device_identifier(packet2) == "APK003"

      # Kenwood TH-D7A: prefix ">", no suffix
      packet3 = %{data_type: :mic_e, destination: "T5TYR2", data_extended: %{comment: ">bar"}}
      assert DeviceParser.extract_device_identifier(packet3) == "APK002"
    end

    test "raw packet string extraction" do
      # Should extract destination and decode as Mic-E (Kenwood special case)
      raw = "CALLSIGN>T5TYR4,OTHER:payload"
      assert DeviceParser.extract_device_identifier(raw) == "APK004"
    end
  end
end
