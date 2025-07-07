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

    # NEW TESTS TO INCREASE COVERAGE

    test "Mic-E packet without comment field falls back to decode_mic_e_tocall" do
      # This tests line 28: decode_mic_e_tocall(dest)
      packet = %{data_type: :mic_e, destination: "T5TYR4"}
      assert DeviceParser.extract_device_identifier(packet) == "APK004"
    end

    test "legacy device identification with no match falls back to decode_mic_e_tocall" do
      # This tests line 22: nil -> decode_mic_e_tocall(dest)
      packet = %{data_type: :mic_e, destination: "T5TYR4", data_extended: %{comment: "UNKNOWN"}}
      assert DeviceParser.extract_device_identifier(packet) == "APK004"
    end

    test "raw packet string with invalid format returns nil" do
      # This tests line 40: _ -> nil
      raw = "INVALID_PACKET_FORMAT"
      assert DeviceParser.extract_device_identifier(raw) == nil
    end

    test "invalid packet type returns nil" do
      # This tests line 44: def extract_device_identifier(_), do: nil
      assert DeviceParser.extract_device_identifier(nil) == nil
      assert DeviceParser.extract_device_identifier(123) == nil
      assert DeviceParser.extract_device_identifier(%{}) == nil
      assert DeviceParser.extract_device_identifier(%{invalid: "data"}) == nil
    end

    test "destination with non-binary value returns nil" do
      # This tests the catch-all clause
      assert DeviceParser.extract_device_identifier(%{destination: 123}) == nil
      assert DeviceParser.extract_device_identifier(%{destination: nil}) == nil
    end
  end

  describe "decode_mic_e_tocall/1" do
    test "all Kenwood special cases" do
      # Test all special cases including the uncovered ones
      assert DeviceParser.decode_mic_e_tocall("T5TYR4") == "APK004"
      # Line 65
      assert DeviceParser.decode_mic_e_tocall("T5TYR3") == "APK003"
      assert DeviceParser.decode_mic_e_tocall("T5TYR2") == "APK002"
      # Line 71
      assert DeviceParser.decode_mic_e_tocall("T5TYR1") == "APK001"
    end

    test "known prefix mappings" do
      # Test all prefix mappings in the @mic_e_prefix_map
      assert DeviceParser.decode_mic_e_tocall("T5T123") == "APK123"
      assert DeviceParser.decode_mic_e_tocall("T5U456") == "APK456"
      assert DeviceParser.decode_mic_e_tocall("T5V789") == "APK789"
      assert DeviceParser.decode_mic_e_tocall("T2T000") == "APN000"
      assert DeviceParser.decode_mic_e_tocall("T2U111") == "APN111"
      assert DeviceParser.decode_mic_e_tocall("T2V222") == "APN222"
      assert DeviceParser.decode_mic_e_tocall("S6T333") == "APW333"
      assert DeviceParser.decode_mic_e_tocall("S6U444") == "APW444"
      assert DeviceParser.decode_mic_e_tocall("S6V555") == "APW555"
    end

    test "unknown prefix returns original destination" do
      # Test the fallback case when prefix is not found
      assert DeviceParser.decode_mic_e_tocall("ZZZ123") == "ZZZ123"
      assert DeviceParser.decode_mic_e_tocall("ABC456") == "ABC456"
    end

    test "non-6-byte destinations are sliced" do
      # This tests line 86: def decode_mic_e_tocall(dest), do: String.slice(dest, 0, 6)
      assert DeviceParser.decode_mic_e_tocall("SHORT") == "SHORT"
      assert DeviceParser.decode_mic_e_tocall("VERYLONGDESTINATION") == "VERYLO"
      assert DeviceParser.decode_mic_e_tocall("") == ""
    end

    test "all Mic-E digit conversion scenarios" do
      # Test all digit conversion cases including the uncovered ones

      # Numeric digits (0-9) - already covered
      assert DeviceParser.decode_mic_e_tocall("T5T000") == "APK000"
      assert DeviceParser.decode_mic_e_tocall("T5T123") == "APK123"
      assert DeviceParser.decode_mic_e_tocall("T5T999") == "APK999"

      # A-J digits (A=0, B=1, ..., J=9) - Line 128
      assert DeviceParser.decode_mic_e_tocall("T5TAAA") == "APK000"
      assert DeviceParser.decode_mic_e_tocall("T5TABC") == "APK012"
      assert DeviceParser.decode_mic_e_tocall("T5TAJJ") == "APK099"

      # P-Y digits (P=0, Q=1, ..., Y=9) - Line 129
      assert DeviceParser.decode_mic_e_tocall("T5TPPP") == "APK000"
      assert DeviceParser.decode_mic_e_tocall("T5TPQR") == "APK012"
      assert DeviceParser.decode_mic_e_tocall("T5TPYY") == "APK099"

      # Mixed digit types
      assert DeviceParser.decode_mic_e_tocall("T5T0A1") == "APK001"
      assert DeviceParser.decode_mic_e_tocall("T5T1P2") == "APK102"
      assert DeviceParser.decode_mic_e_tocall("T5T9JY") == "APK999"
    end

    test "invalid digits return original destination" do
      # This tests line 130: defp mic_e_digit(_), do: nil
      # Characters not in 0-9, A-J, or P-Y should cause the suffix calculation to fail
      # K, L, M are invalid
      assert DeviceParser.decode_mic_e_tocall("T5TKLM") == "T5TKLM"
      # Z is invalid
      assert DeviceParser.decode_mic_e_tocall("T5TZ12") == "T5TZ12"
      # Z is invalid
      assert DeviceParser.decode_mic_e_tocall("T5T12Z") == "T5T12Z"
      # Multiple invalid chars
      assert DeviceParser.decode_mic_e_tocall("T5TZ@#") == "T5TZ@#"
    end

    test "edge cases with special characters" do
      # Test various edge cases
      # Spaces
      assert DeviceParser.decode_mic_e_tocall("T5T   ") == "T5T   "
      # Punctuation
      assert DeviceParser.decode_mic_e_tocall("T5T!!!") == "T5T!!!"
      # Valid case
      assert DeviceParser.decode_mic_e_tocall("T5T123") == "APK123"
    end
  end

  describe "identify_mic_e_legacy_device/1" do
    test "all legacy device patterns" do
      # Test all legacy device patterns
      # TH-D74
      assert DeviceParser.extract_device_identifier(%{
               data_type: :mic_e,
               destination: "T5TYR2",
               data_extended: %{comment: ">random^"}
             }) == "APK004"

      # TH-D72
      assert DeviceParser.extract_device_identifier(%{
               data_type: :mic_e,
               destination: "T5TYR2",
               data_extended: %{comment: ">foo="}
             }) == "APK003"

      # TH-D7A
      assert DeviceParser.extract_device_identifier(%{
               data_type: :mic_e,
               destination: "T5TYR2",
               data_extended: %{comment: ">bar"}
             }) == "APK002"
    end

    test "legacy device patterns with no match" do
      # Test patterns that don't match any legacy device
      packet = %{
        data_type: :mic_e,
        destination: "T5TYR2",
        data_extended: %{comment: "random"}
      }

      # Falls back to decode_mic_e_tocall
      assert DeviceParser.extract_device_identifier(packet) == "APK002"
    end
  end
end
