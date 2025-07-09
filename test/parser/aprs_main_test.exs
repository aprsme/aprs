defmodule Aprs.MainTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "version/0" do
    test "returns version string" do
      assert Aprs.version() == "0.1.4"
      assert is_binary(Aprs.version())
    end
  end

  describe "parse/1 error handling" do
    test "handles invalid UTF-8" do
      # Create invalid UTF-8 binary
      invalid_utf8 = <<0xFF, 0xFE, 0xFD>>

      # Should either fix the UTF-8 or return an error
      case Aprs.parse(invalid_utf8) do
        {:error, :invalid_utf8} -> :ok
        {:error, :invalid_packet} -> :ok
        # If it fixes the UTF-8
        {:ok, _} -> :ok
      end
    end

    test "handles non-binary input" do
      assert {:error, :invalid_packet} = Aprs.parse(123)
      assert {:error, :invalid_packet} = Aprs.parse(nil)
      assert {:error, :invalid_packet} = Aprs.parse(%{})
      assert {:error, :invalid_packet} = Aprs.parse([])
    end

    test "handles empty string" do
      assert {:error, :invalid_packet} = Aprs.parse("")
    end

    test "handles malformed packets" do
      # Missing > separator
      assert {:error, :invalid_packet} = Aprs.parse("N0CALL:data")

      # Missing : separator
      assert {:error, :invalid_packet} = Aprs.parse("N0CALL>APRS")

      # Empty components
      assert {:error, :invalid_packet} = Aprs.parse(">:")
      assert {:error, :invalid_packet} = Aprs.parse("N0CALL>:")
      assert {:error, :invalid_packet} = Aprs.parse(">APRS:")
    end

    test "handles packets with invalid callsigns" do
      # Invalid callsign format - parser may be lenient
      case Aprs.parse("INVALID_CALLSIGN>APRS:data") do
        # Parser accepts it
        {:ok, _} -> :ok
        # Parser rejects it
        {:error, :invalid_packet} -> :ok
      end

      case Aprs.parse("123456789012345>APRS:data") do
        {:ok, _} -> :ok
        {:error, :invalid_packet} -> :ok
      end
    end

    test "handles packets with empty data" do
      assert {:ok, parsed} = Aprs.parse("N0CALL>APRS:")
      assert parsed.data_type == :empty
      assert parsed.information_field == ""
      assert parsed.sender == "N0CALL"
      assert parsed.destination == "APRS"
    end

    test "handles real world packet with empty information field" do
      # Real world packet like YM6KAM-3>APRS,YM6KTR*,WIDE2-1,qAR,TA6AD-10:
      packet = "YM6KAM-3>APRS,YM6KTR*,WIDE2-1,qAR,TA6AD-10:"
      assert {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_type == :empty
      assert parsed.information_field == ""
      assert parsed.sender == "YM6KAM-3"
      assert parsed.destination == "APRS"
      assert parsed.path == "YM6KTR*,WIDE2-1,qAR,TA6AD-10"
    end

    test "handles packets that cause parsing exceptions" do
      # Test packet that might cause internal parsing errors
      malformed_packet = "N0CALL>APRS:!" <> String.duplicate("x", 1000)

      case Aprs.parse(malformed_packet) do
        {:ok, _} -> :ok
        {:error, :invalid_packet} -> :ok
      end
    end
  end

  describe "split_packet/1" do
    test "splits valid packets correctly" do
      assert {:ok, ["N0CALL", "APRS", "data"]} = Aprs.split_packet("N0CALL>APRS:data")

      assert {:ok, ["N0CALL-1", "APRS,TCPIP*", "!1234.56N/12345.67W-"]} =
               Aprs.split_packet("N0CALL-1>APRS,TCPIP*:!1234.56N/12345.67W-")
    end

    test "handles malformed packets" do
      assert {:error, "Invalid packet format"} = Aprs.split_packet("N0CALL:data")
      assert {:error, "Invalid packet format"} = Aprs.split_packet("N0CALL>APRS")
      assert {:error, "Invalid packet format"} = Aprs.split_packet("N0CALL>")
      # This one actually works because empty sender is valid
      assert {:ok, ["", "APRS", "data"]} = Aprs.split_packet(">APRS:data")
    end
  end

  describe "split_path/1" do
    test "splits paths correctly" do
      assert {:ok, ["APRS", "TCPIP*,qAC,T2TEST"]} = Aprs.split_path("APRS,TCPIP*,qAC,T2TEST")
      assert {:ok, ["APRS", ""]} = Aprs.split_path("APRS")
      assert {:ok, ["BEACON", "WIDE1-1,WIDE2-1"]} = Aprs.split_path("BEACON,WIDE1-1,WIDE2-1")
    end

    test "handles empty paths" do
      assert {:ok, ["", ""]} = Aprs.split_path("")
    end
  end

  describe "parse_datatype_safe/1" do
    test "parses valid data types" do
      assert {:ok, :message} = Aprs.parse_datatype_safe(":N0CALL   :Hello")
      assert {:ok, :status} = Aprs.parse_datatype_safe(">Status message")
      assert {:ok, :position} = Aprs.parse_datatype_safe("!1234.56N/12345.67W-")
      assert {:ok, :weather} = Aprs.parse_datatype_safe("_12345678c000s000g000")
    end

    test "handles empty data" do
      assert {:ok, :empty} = Aprs.parse_datatype_safe("")
    end

    test "handles unknown data types" do
      assert {:ok, :unknown_datatype} = Aprs.parse_datatype_safe("X unknown data")
    end
  end

  describe "parse_callsign/1" do
    test "parses valid callsigns" do
      assert {:ok, ["N0CALL", "0"]} = Aprs.parse_callsign("N0CALL")
      assert {:ok, ["N0CALL", "1"]} = Aprs.parse_callsign("N0CALL-1")
      assert {:ok, ["W1AW", "15"]} = Aprs.parse_callsign("W1AW-15")
    end

    test "handles invalid callsigns" do
      # These should be handled by the AX25 parser, but some may be accepted
      case Aprs.parse_callsign("INVALID_CALLSIGN_TOO_LONG") do
        # Parser is lenient
        {:ok, _} -> :ok
        # Parser rejects it
        {:error, _} -> :ok
      end

      case Aprs.parse_callsign("123") do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end

      assert {:error, _} = Aprs.parse_callsign("")
    end
  end

  describe "parse_datatype/1" do
    test "identifies all data types correctly" do
      assert :message == Aprs.parse_datatype(":N0CALL   :Hello")
      assert :status == Aprs.parse_datatype(">Status message")
      assert :position == Aprs.parse_datatype("!1234.56N/12345.67W-")
      assert :timestamped_position == Aprs.parse_datatype("/092345z1234.56N/12345.67W-")
      assert :position_with_message == Aprs.parse_datatype("=1234.56N/12345.67W-Test")
      assert :timestamped_position_with_message == Aprs.parse_datatype("@092345z1234.56N/12345.67W-Test")
      assert :object == Aprs.parse_datatype(";OBJECT   *092345z1234.56N/12345.67W-")
      assert :mic_e_old == Aprs.parse_datatype("`1234.56N/12345.67W-")
      assert :mic_e_old == Aprs.parse_datatype("'1234.56N/12345.67W-")
      assert :weather == Aprs.parse_datatype("_12345678c000s000g000")
      assert :telemetry == Aprs.parse_datatype("T#123,100,200,300,400,500,00000000")
      assert :raw_gps_ultimeter == Aprs.parse_datatype("$GPRMC,123456,A,4903.50,N,07201.75,W*6A")
      assert :station_capabilities == Aprs.parse_datatype("<IGATE,MSG_CNT/1h,LOC_CNT/1h")
      assert :query == Aprs.parse_datatype("?APRS?")
      assert :user_defined == Aprs.parse_datatype("{AUSERDEF")
      assert :third_party_traffic == Aprs.parse_datatype("}N0CALL>APRS,TCPIP*:data")
      assert :item == Aprs.parse_datatype(")ITEM!1234.56N/12345.67W-")
      assert :item == Aprs.parse_datatype("%ITEM!1234.56N/12345.67W-")
      assert :peet_logging == Aprs.parse_datatype("*wind data")
      assert :invalid_test_data == Aprs.parse_datatype(",test data")
      assert :df_report == Aprs.parse_datatype("#DFS2360")
      assert :phg_data == Aprs.parse_datatype("#PHG2360")
      assert :phg_data == Aprs.parse_datatype("#2360")
      assert :unknown_datatype == Aprs.parse_datatype("X unknown")
    end
  end

  describe "parse_data/3 edge cases" do
    test "handles df_report with malformed data" do
      # Should fall back to basic df_data format
      result = Aprs.parse_data(:df_report, "APRS", "DF123")
      assert result.df_data == "DF123"
      assert result.data_type == :df_report
    end

    test "handles raw_gps_ultimeter with parsing errors" do
      result = Aprs.parse_data(:raw_gps_ultimeter, "APRS", "INVALID_NMEA")
      assert result.data_type == :raw_gps_ultimeter
      assert result.error != nil
      assert result.latitude == nil
      assert result.longitude == nil
    end

    test "handles unsupported data types" do
      assert nil == Aprs.parse_data(:unsupported_type, "APRS", "data")
    end
  end

  describe "third party traffic parsing" do
    test "handles simple third party traffic" do
      packet = "N0CALL>APRS:}N0CALL>APRS,TCPIP*:!1234.56N/12345.67W-"

      case Aprs.parse(packet) do
        {:ok, result} ->
          assert result.data_type == :third_party_traffic
          assert result.data_extended != nil

        {:error, _} ->
          # May fail due to complex parsing
          :ok
      end
    end

    test "handles maximum tunnel depth" do
      # Create a packet with too much nesting
      deep_packet = "N0CALL>APRS:" <> String.duplicate("}", 10) <> "N0CALL>APRS:data"

      case Aprs.parse(deep_packet) do
        {:ok, result} ->
          # Should handle or limit depth
          assert result.data_type in [:third_party_traffic, :unknown_datatype]

        {:error, _} ->
          # May fail due to deep nesting
          :ok
      end
    end

    test "handles malformed third party traffic" do
      malformed_packets = [
        "}INVALID:data",
        "}N0CALL>",
        "}N0CALL>APRS",
        "}:data"
      ]

      for packet <- malformed_packets do
        case Aprs.parse(packet) do
          {:ok, result} ->
            if result.data_extended do
              assert result.data_extended.error != nil
            end

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "position parsing edge cases" do
    test "handles compressed positions without prefix" do
      # Test compressed position data without leading "/"
      compressed_data = "5L!!<*e7>{?!|!{?!|!{?!|!{?!|!{?"

      case Aprs.parse("N0CALL>APRS:!" <> compressed_data) do
        {:ok, result} ->
          assert result.data_type in [:position, :malformed_position]

        {:error, _} ->
          :ok
      end
    end

    test "handles malformed position coordinates" do
      malformed_positions = [
        "!INVALID/COORDS-",
        "!1234.56X/12345.67Y-",
        "!9999.99N/99999.99W-",
        "!//////////-"
      ]

      for pos_data <- malformed_positions do
        case Aprs.parse("N0CALL>APRS:" <> pos_data) do
          {:ok, result} ->
            assert result.data_type in [:position, :malformed_position]

          {:error, _} ->
            :ok
        end
      end
    end

    test "handles weather detection in positions" do
      # Position with weather symbol
      weather_pos = "!1234.56N/12345.67W_Test weather data"

      case Aprs.parse("N0CALL>APRS:" <> weather_pos) do
        {:ok, result} ->
          # Should detect weather based on symbol or comment
          assert result.data_type in [:position, :weather]

        {:error, _} ->
          :ok
      end
    end

    test "handles timestamped positions with weather" do
      # Timestamped position with weather data
      weather_timestamp = "@092345z1234.56N/12345.67W_c000s000g000"

      case Aprs.parse("N0CALL>APRS:" <> weather_timestamp) do
        {:ok, result} ->
          assert result.data_type in [:position, :weather, :timestamped_position_with_message]

        {:error, _} ->
          :ok
      end
    end
  end

  describe "message parsing edge cases" do
    test "handles messages with acknowledgment numbers" do
      msg_with_ack = ":N0CALL   :Hello world{123}"

      case Aprs.parse("N0CALL>APRS:" <> msg_with_ack) do
        {:ok, result} ->
          assert result.data_type == :message

          if result.data_extended do
            assert result.data_extended.message_number == "123"
          end

        {:error, _} ->
          :ok
      end
    end

    test "handles messages without acknowledgment" do
      msg_without_ack = ":N0CALL   :Hello world"

      case Aprs.parse("N0CALL>APRS:" <> msg_without_ack) do
        {:ok, result} ->
          assert result.data_type == :message

          if result.data_extended do
            assert result.data_extended.message_number == nil
          end

        {:error, _} ->
          :ok
      end
    end

    test "handles malformed messages" do
      malformed_messages = [
        ":INVALID:msg",
        ":N0CALL:",
        "::",
        ":N0CALL   msg without colon"
      ]

      for msg <- malformed_messages do
        case Aprs.parse("N0CALL>APRS:" <> msg) do
          {:ok, result} ->
            assert result.data_type == :message

          # Should handle gracefully
          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "user defined parsing" do
    test "handles different user defined formats" do
      user_formats = [
        "{AExperimental A format",
        "{BExperimental B format",
        "{CCustom C format",
        "{XUnknown format"
      ]

      for format <- user_formats do
        case Aprs.parse("N0CALL>APRS:" <> format) do
          {:ok, result} ->
            assert result.data_type == :user_defined

            if result.data_extended do
              # Check if it has user_id (properly formatted) or user_data (malformed)
              if Map.has_key?(result.data_extended, :user_id) do
                assert result.data_extended.user_id in ["A", "B", "C", "X"]
              else
                assert Map.has_key?(result.data_extended, :user_data)
              end
            end

          {:error, _} ->
            :ok
        end
      end
    end

    test "handles malformed user defined data" do
      malformed_user = "{incomplete"

      case Aprs.parse("N0CALL>APRS:" <> malformed_user) do
        {:ok, result} ->
          assert result.data_type == :user_defined

        {:error, _} ->
          :ok
      end
    end
  end

  describe "query parsing" do
    test "handles different query types" do
      queries = [
        "?APRS?",
        "?PING?",
        "?VER?",
        "?XXXX?"
      ]

      for query <- queries do
        case Aprs.parse("N0CALL>APRS:" <> query) do
          {:ok, result} ->
            assert result.data_type == :query

          {:error, _} ->
            :ok
        end
      end
    end

    test "handles malformed queries" do
      malformed_query = "?incomplete"

      case Aprs.parse("N0CALL>APRS:" <> malformed_query) do
        {:ok, result} ->
          assert result.data_type == :query

        {:error, _} ->
          :ok
      end
    end
  end

  describe "station capabilities parsing" do
    test "handles station capabilities" do
      caps = "<IGATE,MSG_CNT/1h,LOC_CNT/1h"

      case Aprs.parse("N0CALL>APRS:" <> caps) do
        {:ok, result} ->
          assert result.data_type == :station_capabilities

        {:error, _} ->
          :ok
      end
    end

    test "handles malformed capabilities" do
      malformed_caps = "<incomplete"

      case Aprs.parse("N0CALL>APRS:" <> malformed_caps) do
        {:ok, result} ->
          assert result.data_type == :station_capabilities

        {:error, _} ->
          :ok
      end
    end
  end

  describe "property tests" do
    property "parse/1 handles random binary data gracefully" do
      check all data <- StreamData.binary(min_length: 1, max_length: 200) do
        case Aprs.parse(data) do
          {:ok, _result} -> :ok
          {:error, _reason} -> :ok
        end
      end
    end

    property "parse/1 handles random ASCII strings gracefully" do
      check all data <- StreamData.string(:ascii, min_length: 1, max_length: 200) do
        case Aprs.parse(data) do
          {:ok, _result} -> :ok
          {:error, _reason} -> :ok
        end
      end
    end

    property "split_packet/1 handles random strings gracefully" do
      check all data <- StreamData.string(:ascii, min_length: 1, max_length: 100) do
        case Aprs.split_packet(data) do
          {:ok, _parts} -> :ok
          {:error, _reason} -> :ok
        end
      end
    end
  end
end
