defmodule Aprs.DeviceParserTest do
  use ExUnit.Case, async: true

  alias Aprs.DeviceParser

  describe "extract_device_identifier/1 for packet maps" do
    test "returns the first six destination characters for non-Mic-E packets" do
      assert DeviceParser.extract_device_identifier(%{destination: "APRSWX-12"}) == "APRSWX"
      assert DeviceParser.extract_device_identifier(%{destination: "SHORT"}) == "SHORT"
    end

    test "identifies Kenwood handhelds from the Mic-E comment" do
      assert mic_e_device(:mic_e, ">status^") == "APK004"
      assert mic_e_device(:mic_e_old, ">status=") == "APK003"
      assert mic_e_device(:mic_e, ">status") == "APK002"
    end

    test "identifies Kenwood mobile radios from the Mic-E comment" do
      assert mic_e_device(:mic_e, "]status=") == "APK102"
      assert mic_e_device(:mic_e_old, "]status") == "APK101"
    end

    test "matches a specific suffix before the prefix-only device" do
      assert mic_e_device(:mic_e, ">status^") == "APK004"
      assert mic_e_device(:mic_e, "]status=") == "APK102"
      assert mic_e_device(:mic_e, ">status_#") == "APY008"
    end

    test "identifies Yaesu radios from a backtick DTI and comment suffix" do
      assert mic_e_device(:mic_e, "status_\"") == "APY350"
      assert mic_e_device(:mic_e, "status_#") == "APY008"
      assert mic_e_device(:mic_e, "status_$") == "APY01D"
      assert mic_e_device(:mic_e, "status_%") == "APY400"
      assert mic_e_device(:mic_e, "status_(") == "APY02D"
    end

    test "does not apply backtick-DTI Yaesu identifiers to apostrophe packets" do
      assert mic_e_device(:mic_e_old, "status_%") == nil
    end

    test "accepts a flattened Mic-E comment" do
      packet = %{data_type: :mic_e, destination: "T7SYWU", comment: ">status^"}

      assert DeviceParser.extract_device_identifier(packet) == "APK004"
    end

    test "does not fabricate a TOCALL from the encoded Mic-E destination" do
      assert mic_e_device(:mic_e, "unidentified") == nil

      assert DeviceParser.extract_device_identifier(%{
               data_type: :mic_e_old,
               destination: "T5TYR4"
             }) == nil
    end

    test "returns nil for unsupported values" do
      assert DeviceParser.extract_device_identifier(nil) == nil
      assert DeviceParser.extract_device_identifier(123) == nil
      assert DeviceParser.extract_device_identifier(%{}) == nil
      assert DeviceParser.extract_device_identifier(%{destination: 123}) == nil
    end
  end

  describe "extract_device_identifier/1 for raw packets" do
    test "extracts a destination when the header includes a path" do
      assert DeviceParser.extract_device_identifier("CALLSIGN>APRSWX,WIDE1-1:payload") == "APRSWX"
    end

    test "extracts a destination when the header has no path" do
      assert DeviceParser.extract_device_identifier("CALLSIGN>APRSWX:payload") == "APRSWX"
    end

    test "limits a raw destination to six characters without Mic-E decoding" do
      assert DeviceParser.extract_device_identifier("CALLSIGN>T5TYR4:payload") == "T5TYR4"
    end

    test "returns nil for a malformed raw packet" do
      assert DeviceParser.extract_device_identifier("INVALID_PACKET_FORMAT") == nil
    end
  end

  defp mic_e_device(data_type, comment) do
    DeviceParser.extract_device_identifier(%{
      data_type: data_type,
      destination: "T7SYWU",
      data_extended: %{comment: comment}
    })
  end
end
