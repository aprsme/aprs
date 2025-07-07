defmodule AprsTest do
  use ExUnit.Case

  alias Aprs

  describe "parse/1" do
    test "parses valid APRS packet" do
      packet = "CALLSIGN>APRSWX,TCPIP*:!4042.12N/07415.67W>Test message"
      result = Aprs.parse(packet)

      assert {:ok, parsed} = result
      assert parsed.sender == "CALLSIGN"
      assert parsed.path == "APRSWX,TCPIP*"
      assert parsed.destination == "APRSWX"
      assert parsed.data_type == :position
      assert parsed.base_callsign == "CALLSIGN"
      assert parsed.ssid == nil
      assert is_map(parsed.data_extended)
      assert is_struct(parsed.received_at, DateTime)
    end

    test "parses packet with SSID" do
      packet = "CALLSIGN-1>APRSWX,TCPIP*:!4042.12N/07415.67W>Test message"
      result = Aprs.parse(packet)

      assert {:ok, parsed} = result
      assert parsed.base_callsign == "CALLSIGN"
      assert parsed.ssid == "1"
    end

    test "parses packet with numeric SSID" do
      packet = "CALLSIGN-15>APRSWX,TCPIP*:!4042.12N/07415.67W>Test message"
      result = Aprs.parse(packet)

      assert {:ok, parsed} = result
      assert parsed.base_callsign == "CALLSIGN"
      assert parsed.ssid == "15"
    end

    test "handles invalid UTF-8" do
      # Create a string with invalid UTF-8 bytes
      invalid_utf8 = <<0xFF, 0xFE, 0xFD, "CALLSIGN>APRSWX:Test">>
      result = Aprs.parse(invalid_utf8)

      assert {:ok, parsed} = result
      assert parsed.sender == "CALLSIGN"
    end

    test "returns error for non-binary input" do
      assert Aprs.parse(123) == {:error, :invalid_packet}
      assert Aprs.parse(nil) == {:error, :invalid_packet}
      assert Aprs.parse(:atom) == {:error, :invalid_packet}
    end

    test "returns error for invalid packet format" do
      assert Aprs.parse("INVALID_PACKET") == {:error, :invalid_packet}
      assert Aprs.parse("CALLSIGN") == {:error, :invalid_packet}
      assert Aprs.parse("CALLSIGN>") == {:error, :invalid_packet}
    end

    test "returns error for empty string" do
      assert Aprs.parse("") == {:error, :invalid_packet}
    end
  end

  describe "split_packet/1" do
    test "splits valid packet" do
      packet = "CALLSIGN>APRSWX,TCPIP*:Test data"
      result = Aprs.split_packet(packet)

      assert {:ok, ["CALLSIGN", "APRSWX,TCPIP*", "Test data"]} = result
    end

    test "splits packet without path" do
      packet = "CALLSIGN>APRSWX:Test data"
      result = Aprs.split_packet(packet)

      assert {:ok, ["CALLSIGN", "APRSWX", "Test data"]} = result
    end

    test "returns error for missing delimiter" do
      assert Aprs.split_packet("CALLSIGN APRSWX:Test") == {:error, "Invalid packet format"}
      assert Aprs.split_packet("CALLSIGN") == {:error, "Invalid packet format"}
    end

    test "returns error for missing colon" do
      assert Aprs.split_packet("CALLSIGN>APRSWX") == {:error, "Invalid packet format"}
    end
  end

  describe "split_path/1" do
    test "splits path with destination and digipeaters" do
      path = "APRSWX,TCPIP*,qAR,CALLSIGN"
      result = Aprs.split_path(path)

      assert {:ok, ["APRSWX", "TCPIP*,qAR,CALLSIGN"]} = result
    end

    test "splits path with only destination" do
      path = "APRSWX"
      result = Aprs.split_path(path)

      assert {:ok, ["APRSWX", ""]} = result
    end

    test "returns error for invalid path" do
      assert Aprs.split_path("") == {:error, "Invalid path format"}
    end
  end

  describe "parse_callsign/1" do
    test "parses callsign without SSID" do
      result = Aprs.parse_callsign("CALLSIGN")
      assert {:ok, ["CALLSIGN", nil]} = result
    end

    test "parses callsign with SSID" do
      result = Aprs.parse_callsign("CALLSIGN-1")
      assert {:ok, ["CALLSIGN", "1"]} = result
    end

    test "parses callsign with numeric SSID" do
      result = Aprs.parse_callsign("CALLSIGN-15")
      assert {:ok, ["CALLSIGN", "15"]} = result
    end

    test "returns error for invalid callsign" do
      assert Aprs.parse_callsign("") == {:error, "Invalid callsign format"}
    end
  end

  describe "parse_datatype_safe/1" do
    test "returns error for empty data" do
      assert Aprs.parse_datatype_safe("") == {:error, "Empty data"}
    end

    test "returns ok for valid data" do
      assert Aprs.parse_datatype_safe("!4042.12N/07415.67W") == {:ok, :position}
      assert Aprs.parse_datatype_safe(":ADDRESSEE:Message") == {:ok, :message}
      assert Aprs.parse_datatype_safe(">Status message") == {:ok, :status}
    end
  end

  describe "parse_datatype/1" do
    test "identifies position packets" do
      assert Aprs.parse_datatype("!4042.12N/07415.67W") == :position
      assert Aprs.parse_datatype("=4042.12N/07415.67W>Message") == :position_with_message
    end

    test "identifies timestamped position packets" do
      assert Aprs.parse_datatype("/123456/4042.12N/07415.67W") == :timestamped_position
      assert Aprs.parse_datatype("@123456/4042.12N/07415.67W>Message") == :timestamped_position_with_message
    end

    test "identifies message packets" do
      assert Aprs.parse_datatype(":ADDRESSEE:Message text") == :message
    end

    test "identifies status packets" do
      assert Aprs.parse_datatype(">Status message") == :status
    end

    test "identifies object packets" do
      assert Aprs.parse_datatype(";OBJECT    *123456/4042.12N/07415.67W") == :object
    end

    test "identifies item packets" do
      assert Aprs.parse_datatype("%ITEM      *123456/4042.12N/07415.67W") == :item
      assert Aprs.parse_datatype(")ITEM      *123456/4042.12N/07415.67W") == :item
    end

    test "identifies weather packets" do
      assert Aprs.parse_datatype("_123456/4042.12N/07415.67W.../...g...t...r...p...h..b") == :weather
    end

    test "identifies telemetry packets" do
      assert Aprs.parse_datatype("T#123,456,789,012,345,678,Unit:Test") == :telemetry
    end

    test "identifies Mic-E packets" do
      assert Aprs.parse_datatype("`4042.12N/07415.67W") == :mic_e_old
      assert Aprs.parse_datatype("'4042.12N/07415.67W") == :mic_e_old
    end

    test "identifies raw GPS packets" do
      assert Aprs.parse_datatype("$GPGGA,123456,4042.1234,N,07415.6789,W,1,8,1.2,100,M,0,M,,*6A") == :raw_gps_ultimeter
    end

    test "identifies station capabilities" do
      assert Aprs.parse_datatype("<CAPABILITIES>") == :station_capabilities
    end

    test "identifies query packets" do
      assert Aprs.parse_datatype("?QUERY") == :query
    end

    test "identifies user defined packets" do
      assert Aprs.parse_datatype("{USER_DATA}") == :user_defined
    end

    test "identifies third party traffic" do
      assert Aprs.parse_datatype("}THIRD_PARTY") == :third_party_traffic
    end

    test "identifies peet logging" do
      assert Aprs.parse_datatype("*PEET_LOG") == :peet_logging
    end

    test "identifies invalid test data" do
      assert Aprs.parse_datatype(",INVALID") == :invalid_test_data
    end

    test "identifies DF reports" do
      assert Aprs.parse_datatype("#DFS1234Comment") == :df_report
    end

    test "identifies PHG data" do
      assert Aprs.parse_datatype("#PHG1234Comment") == :phg_data
      assert Aprs.parse_datatype("#PHG1234") == :phg_data
    end

    test "returns unknown for unrecognized types" do
      assert Aprs.parse_datatype("UNKNOWN") == :unknown_datatype
      assert Aprs.parse_datatype("") == :unknown_datatype
    end
  end

  describe "parse_data/3" do
    test "parses position data" do
      data = "4042.12N/07415.67W>Test message"
      result = Aprs.parse_data(:position, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :position
    end

    test "parses message data" do
      data = ":ADDRESSEE:Message text{123}"
      result = Aprs.parse_data(:message, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :message
      assert result.addressee == "ADDRESSEE"
      assert result.message_text == "Message text"
      assert result.message_number == "123"
    end

    test "parses message data without message number" do
      data = ":ADDRESSEE:Message text"
      result = Aprs.parse_data(:message, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :message
      assert result.addressee == "ADDRESSEE"
      assert result.message_text == "Message text"
      assert result.message_number == nil
    end

    test "parses weather data" do
      data = "123456/4042.12N/07415.67W.../...g...t...r...p...h..b"
      result = Aprs.parse_data(:weather, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :weather
    end

    test "parses telemetry data" do
      data = "#123,456,789,012,345,678,Unit:Test"
      result = Aprs.parse_data(:telemetry, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :telemetry
    end

    test "parses status data" do
      data = "Status message"
      result = Aprs.parse_data(:status, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :status
    end

    test "parses object data" do
      data = "OBJECT    *123456/4042.12N/07415.67W"
      result = Aprs.parse_data(:object, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :object
    end

    test "parses item data" do
      data = "ITEM      *123456/4042.12N/07415.67W"
      result = Aprs.parse_data(:item, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :item
    end

    test "parses Mic-E data" do
      data = "4042.12N/07415.67W"
      result = Aprs.parse_data(:mic_e, "T5TYR4", data)

      assert is_map(result)
      assert result.data_type == :mic_e
    end

    test "parses PHG data" do
      data = "PHG1234Comment"
      result = Aprs.parse_data(:phg_data, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :phg_data
    end

    test "parses DF report data" do
      data = "DFS1234Comment"
      result = Aprs.parse_data(:df_report, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :df_report
      assert is_tuple(result.df_strength)
      assert is_tuple(result.height)
      assert is_tuple(result.gain)
      assert is_tuple(result.directivity)
      assert result.comment == "Comment"
    end

    test "parses DF report data without comment" do
      data = "DFS1234"
      result = Aprs.parse_data(:df_report, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :df_report
      assert result.df_data == "DFS1234"
    end

    test "parses raw GPS data" do
      data = "$GPGGA,123456,4042.1234,N,07415.6789,W,1,8,1.2,100,M,0,M,,*6A"
      result = Aprs.parse_data(:raw_gps_ultimeter, "APRSWX", data)

      assert is_map(result)
      assert result.data_type == :raw_gps_ultimeter
      assert result.error == "NMEA parsing not implemented"
    end

    test "returns nil for unknown data type" do
      result = Aprs.parse_data(:unknown_type, "APRSWX", "data")
      assert result == nil
    end
  end

  describe "edge cases" do
    test "handles packets with special characters" do
      packet = "CALLSIGN>APRSWX:!4042.12N/07415.67W>Test with special chars: @#$%^&*()"
      result = Aprs.parse(packet)

      assert {:ok, parsed} = result
      assert parsed.data_type == :position
    end

    test "handles packets with unicode characters" do
      packet = "CALLSIGN>APRSWX:!4042.12N/07415.67W>Test with unicode: café résumé"
      result = Aprs.parse(packet)

      assert {:ok, parsed} = result
      assert parsed.data_type == :position
    end

    test "handles very long packets" do
      long_message = String.duplicate("A", 1000)
      packet = "CALLSIGN>APRSWX:#{long_message}"
      result = Aprs.parse(packet)

      assert {:ok, parsed} = result
      assert parsed.data_type == :phg_data
    end
  end
end
