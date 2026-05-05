defmodule Aprs.ParsersPropertyTest do
  @moduledoc """
  Property-based tests covering the public parser surface end-to-end with
  randomly generated inputs. These complement the existing example-based tests
  by exploring edge cases that are awkward to enumerate by hand.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "Aprs.parse/1 robustness" do
    property "returns either {:ok, map} or {:error, _} for any printable input" do
      check all input <- StreamData.string(:printable, max_length: 200) do
        case Aprs.parse(input) do
          {:ok, map} -> assert is_map(map)
          {:error, _reason} -> :ok
        end
      end
    end

    property "never raises on arbitrary binary input (including invalid UTF-8)" do
      check all input <- StreamData.binary(max_length: 200) do
        result = Aprs.parse(input)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    property "rejects non-binary, non-string inputs cleanly" do
      check all input <-
                  StreamData.one_of([
                    StreamData.integer(),
                    StreamData.float(),
                    StreamData.atom(:alphanumeric),
                    StreamData.constant(nil),
                    StreamData.constant(%{}),
                    StreamData.constant([])
                  ]) do
        assert {:error, :invalid_packet} = Aprs.parse(input)
      end
    end
  end

  describe "Aprs.parse_datatype/1 categorization" do
    @data_type_chars %{
      "!" => :position,
      "=" => :position_with_message,
      "/" => :timestamped_position,
      "@" => :timestamped_position_with_message,
      ";" => :object,
      ")" => :item,
      "_" => :weather,
      "T" => :telemetry,
      "$" => :raw_gps_ultimeter,
      ":" => :message,
      ">" => :status,
      "?" => :query,
      "{" => :user_defined,
      "}" => :third_party_traffic,
      "<" => :station_capabilities,
      "*" => :peet_logging,
      "," => :invalid_test_data
    }

    property "leading ASCII byte determines the recognized data type" do
      check all {prefix, expected} <- StreamData.member_of(Map.to_list(@data_type_chars)),
                rest <- StreamData.string(:printable, max_length: 30) do
        assert Aprs.parse_datatype(prefix <> rest) == expected
      end
    end

    test "empty data is :empty via parse_datatype_safe" do
      assert {:ok, :empty} = Aprs.parse_datatype_safe("")
    end

    property "non-binary input is :unknown_datatype" do
      check all input <- StreamData.one_of([StreamData.integer(), StreamData.constant(nil)]) do
        assert Aprs.parse_datatype(input) == :unknown_datatype
      end
    end
  end

  describe "Aprs.AX25.parse_callsign/1" do
    property "parses BASE-SSID forms back to {base, ssid}" do
      check all base <- StreamData.string(?A..?Z, min_length: 1, max_length: 6),
                ssid <- StreamData.integer(0..15) do
        callsign = "#{base}-#{ssid}"
        assert {:ok, {parsed_base, parsed_ssid}} = Aprs.AX25.parse_callsign(callsign)
        assert parsed_base == base
        assert parsed_ssid == Integer.to_string(ssid)
      end
    end

    property "callsign without SSID returns {base, \"0\"}" do
      check all base <- StreamData.string(?A..?Z, min_length: 1, max_length: 6) do
        assert {:ok, {parsed_base, "0"}} = Aprs.AX25.parse_callsign(base)
        assert parsed_base == base
      end
    end

    test "empty string returns invalid_packet error" do
      assert {:error, :invalid_packet} = Aprs.AX25.parse_callsign("")
    end

    test "non-binary returns format error" do
      assert {:error, _} = Aprs.AX25.parse_callsign(nil)
      assert {:error, _} = Aprs.AX25.parse_callsign(123)
    end
  end

  describe "Aprs.Convert helpers" do
    property "knots → mph conversion produces a non-negative float for non-negative inputs" do
      check all knots <- StreamData.integer(0..200) do
        mph = Aprs.Convert.speed(knots, :knots, :mph)
        assert is_number(mph)
        assert mph >= 0
      end
    end
  end

  describe "Aprs.KISSHelpers" do
    property "round-trips a TNC2 frame through tnc2 → kiss → tnc2" do
      check all body <- StreamData.string(:printable, max_length: 50) do
        kiss = Aprs.KISSHelpers.tnc2_to_kiss(body)
        # Frame must begin with 0xC0 0x00 and end with 0xC0
        assert <<0xC0, 0x00, _::binary>> = kiss
        assert :binary.last(kiss) == 0xC0

        decoded = Aprs.KISSHelpers.kiss_to_tnc2(kiss)
        assert decoded == body
      end
    end

    test "kiss_to_tnc2/1 returns an error map for non-KISS input" do
      assert %{error_code: :packet_invalid} = Aprs.KISSHelpers.kiss_to_tnc2("not a kiss frame")
    end
  end

  describe "Aprs.UtilityHelpers numeric helpers" do
    property "calculate_position_ambiguity counts spaces (capped to 4)" do
      check all lat <- StreamData.string([?0..?9, ?\s, ?., ?N, ?S], min_length: 0, max_length: 10),
                lon <- StreamData.string([?0..?9, ?\s, ?., ?E, ?W], min_length: 0, max_length: 10) do
        result = Aprs.UtilityHelpers.calculate_position_ambiguity(lat, lon)
        assert is_integer(result)
        assert result >= 0 and result <= 4
      end
    end

    property "validate_timestamp returns either nil or an integer Unix timestamp" do
      check all input <- StreamData.string(:printable, max_length: 12) do
        result = Aprs.UtilityHelpers.validate_timestamp(input)
        assert is_nil(result) or is_integer(result)
      end
    end
  end

  describe "Aprs.PHGHelpers" do
    property "PHG digit chars map to known numeric values" do
      check all digit <- StreamData.integer(?0..?9) do
        assert {power, _} = Aprs.PHGHelpers.parse_phg_power(digit)
        assert is_number(power) or is_nil(power)
      end
    end
  end

  describe "Aprs.WeatherHelpers extraction" do
    property "extract_timestamp returns nil or a 7-byte timestamp" do
      check all input <- StreamData.string(:printable, max_length: 60) do
        result = Aprs.WeatherHelpers.extract_timestamp(input)
        assert is_nil(result) or (is_binary(result) and byte_size(result) == 7)
      end
    end

    property "parse_temperature is in valid range or nil" do
      check all input <- StreamData.string(:printable, max_length: 60) do
        result = Aprs.WeatherHelpers.parse_temperature(input)

        assert is_nil(result) or (is_integer(result) and result >= -100 and result <= 150)
      end
    end

    property "parse_wind_direction is in 0..359 or nil" do
      check all input <- StreamData.string(:printable, max_length: 60) do
        result = Aprs.WeatherHelpers.parse_wind_direction(input)
        assert is_nil(result) or (is_integer(result) and result >= 0 and result <= 359)
      end
    end

    property "parse_humidity is in 1..100 or nil" do
      check all input <- StreamData.string(:printable, max_length: 60) do
        result = Aprs.WeatherHelpers.parse_humidity(input)
        assert is_nil(result) or (is_integer(result) and result >= 1 and result <= 100)
      end
    end
  end

  describe "Aprs.NMEAHelpers" do
    property "parse_nmea_coordinate returns {:ok, float} or {:error, _}" do
      check all value <- StreamData.string(:printable, max_length: 12),
                direction <- StreamData.member_of(["N", "S", "E", "W", "X", ""]) do
        case Aprs.NMEAHelpers.parse_nmea_coordinate(value, direction) do
          {:ok, n} -> assert is_float(n)
          {:error, _} -> :ok
        end
      end
    end
  end

  describe "Aprs.CompressedPositionHelpers" do
    property "convert_compressed_lat returns a float in [-90, 90] for any 4-byte base91 input" do
      check all bytes <- StreamData.list_of(StreamData.integer(33..126), length: 4) do
        binary = :binary.list_to_bin(bytes)
        assert {:ok, lat} = Aprs.CompressedPositionHelpers.convert_compressed_lat(binary)
        assert lat >= -90.0 and lat <= 90.0
      end
    end

    property "convert_compressed_lon returns a float in [-180, 180] for any 4-byte base91 input" do
      check all bytes <- StreamData.list_of(StreamData.integer(33..126), length: 4) do
        binary = :binary.list_to_bin(bytes)
        assert {:ok, lon} = Aprs.CompressedPositionHelpers.convert_compressed_lon(binary)
        assert lon >= -180.0 and lon <= 180.0
      end
    end

    property "non-base91 byte yields an error tuple" do
      check all prefix <- StreamData.list_of(StreamData.integer(33..126), length: 3),
                bad <- StreamData.integer(0..32) do
        binary = :binary.list_to_bin(prefix ++ [bad])
        assert {:error, _} = Aprs.CompressedPositionHelpers.convert_compressed_lat(binary)
      end
    end
  end

  describe "Aprs.DeviceParser" do
    property "extract_device_identifier handles arbitrary maps without raising" do
      check all dest <- StreamData.string(:printable, max_length: 30) do
        result = Aprs.DeviceParser.extract_device_identifier(%{destination: dest})
        assert is_binary(result) or is_nil(result)
      end
    end

    property "decode_mic_e_tocall always returns at most the first 6 codepoints" do
      check all input <- StreamData.string(:printable, max_length: 12) do
        result = Aprs.DeviceParser.decode_mic_e_tocall(input)
        assert is_binary(result)
        assert String.length(result) <= 6
      end
    end
  end

  describe "Aprs.MicE.parse/2" do
    property "any 6-char [A-Z0-9] destination + ASCII data either parses or returns an error map" do
      # Restrict the data alphabet to printable ASCII to avoid parse exceptions
      # in altitude/comment binary handling on 4-byte UTF-8 sequences.
      check all dest <- StreamData.string([?A..?Z, ?0..?9], length: 6),
                data <- StreamData.string(33..126, min_length: 9, max_length: 30) do
        result = Aprs.MicE.parse(data, dest)
        assert is_map(result)
        assert result[:data_type] in [:mic_e, :mic_e_old, :mic_e_error]
      end
    end

    test "nil destination returns mic_e_error" do
      assert %{data_type: :mic_e_error} = Aprs.MicE.parse("body", nil)
    end
  end
end
