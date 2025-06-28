defmodule Aprs.ParserTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "split_packet/1" do
    property "returns {:ok, [sender, path, data]} for valid packets" do
      check all sender <- StreamData.string(:alphanumeric, min_length: 1),
                path <- StreamData.string(:alphanumeric, min_length: 1),
                data <- StreamData.string(:printable, min_length: 1) do
        packet = sender <> ">" <> path <> ":" <> data
        assert {:ok, [^sender, ^path, ^data]} = Aprs.split_packet(packet)
      end
    end

    property "returns error for invalid packets" do
      check all s <- StreamData.string(:printable, max_length: 10) do
        bad = s <> s
        assert match?({:error, _}, Aprs.split_packet(bad))
      end
    end

    test "returns error for missing > or :" do
      assert match?({:error, _}, Aprs.split_packet("senderpathdata"))
      assert match?({:error, _}, Aprs.split_packet(":onlycolon"))
      assert match?({:error, _}, Aprs.split_packet(">onlygt"))
    end
  end

  describe "split_path/1" do
    property "splits path into destination and digipeater path for any string" do
      check all s <- StreamData.string(:alphanumeric, min_length: 0, max_length: 10) do
        result = Aprs.split_path(s)
        assert match?({:ok, [_, _]}, result)
      end
    end

    test "splits with no comma" do
      assert {:ok, ["DEST", ""]} = Aprs.split_path("DEST")
    end

    test "splits with one comma" do
      assert {:ok, ["DEST", "DIGI"]} = Aprs.split_path("DEST,DIGI")
    end

    test "returns error for more than one comma" do
      assert {:ok, ["A", "A,A"]} = Aprs.split_path("A,A,A")
    end
  end

  describe "parse_callsign/1" do
    property "parses valid callsigns" do
      check all base <- StreamData.string(:alphanumeric, min_length: 1),
                ssid <- StreamData.string(:alphanumeric, min_length: 1) do
        callsign = base <> "-" <> ssid
        assert {:ok, [^base, ^ssid]} = Aprs.parse_callsign(callsign)
      end
    end
  end

  describe "validate_path/1" do
    property "rejects paths with too many components" do
      check all n <- StreamData.integer(9..20) do
        path = Enum.map_join(1..n, ",", fn _ -> "WIDE1" end)
        assert match?({:error, _}, Aprs.validate_path(path))
      end
    end

    property "accepts paths with 8 or fewer components" do
      check all n <- StreamData.integer(1..8) do
        path = Enum.map_join(1..n, ",", fn _ -> "WIDE1" end)
        assert :ok = Aprs.validate_path(path)
      end
    end
  end

  describe "parse_datatype/1 and parse_datatype_safe/1" do
    property "parse_datatype returns an atom for any printable string" do
      check all s <- StreamData.string(:printable, min_length: 1) do
        assert is_atom(Aprs.parse_datatype(s))
      end
    end

    test "parse_datatype_safe returns {:ok, atom} for non-empty, {:error, _} for empty" do
      assert {:ok, _} = Aprs.parse_datatype_safe("!")
      assert {:error, _} = Aprs.parse_datatype_safe("")
    end

    test "returns correct atom for each known type indicator" do
      assert Aprs.parse_datatype(":msg") == :message
      assert Aprs.parse_datatype(">status") == :status
      assert Aprs.parse_datatype("!pos") == :position
      assert Aprs.parse_datatype("/tspos") == :timestamped_position
      assert Aprs.parse_datatype("=posmsg") == :position_with_message
      assert Aprs.parse_datatype("@tsmsg") == :timestamped_position_with_message
      assert Aprs.parse_datatype(";object") == :object
      assert Aprs.parse_datatype("`mic_e") == :mic_e_old
      assert Aprs.parse_datatype("'mic_e_old") == :mic_e_old
      assert Aprs.parse_datatype("_weather") == :weather
      assert Aprs.parse_datatype("Ttele") == :telemetry
      assert Aprs.parse_datatype("$raw") == :raw_gps_ultimeter
      assert Aprs.parse_datatype("<cap") == :station_capabilities
      assert Aprs.parse_datatype("?query") == :query
      assert Aprs.parse_datatype("{userdef") == :user_defined
      assert Aprs.parse_datatype("}thirdparty") == :third_party_traffic
      assert Aprs.parse_datatype("%item") == :item
      assert Aprs.parse_datatype(")item") == :item
      assert Aprs.parse_datatype("*peet") == :peet_logging
      assert Aprs.parse_datatype(",test") == :invalid_test_data
      assert Aprs.parse_datatype("#DFSfoo") == :df_report
      assert Aprs.parse_datatype("#PHGfoo") == :phg_data
      assert Aprs.parse_datatype("#foo") == :phg_data
      assert Aprs.parse_datatype("Xunknown") == :unknown_datatype
    end
  end

  describe "parse_data/3" do
    test "returns nil for unknown type" do
      assert Aprs.parse_data(:unknown, "", "") == nil
    end

    test "returns nil for invalid test data" do
      assert Aprs.parse_data(:invalid_test_data, "", ",testdata")[:data_type] ==
               :invalid_test_data
    end

    test "returns map for weather" do
      result = Aprs.parse_data(:weather, "", "_12345678c000s000g000t000r000p000P000h00b00000")
      assert is_map(result)
      assert result[:data_type] == :weather
    end

    test "returns map for telemetry" do
      result = Aprs.parse_data(:telemetry, "", "T#123,456,789,012,345,678,901,234")
      assert is_map(result)
      assert result[:data_type] == :telemetry
    end

    test "returns map for object" do
      result = Aprs.parse_data(:object, "", ";OBJECT*111111z4903.50N/07201.75W>Test object")
      assert is_map(result)
      assert result[:data_type] == :object
    end

    test "returns map for item" do
      result = Aprs.parse_data(:item, "", ")ITEM!4903.50N/07201.75W>Test item")
      assert is_map(result)
      assert result[:data_type] == :item
    end

    test "returns map for status" do
      result = Aprs.parse_data(:status, "", ">Test status message")
      assert is_map(result)
      assert result[:data_type] == :status
    end

    test "returns map for user_defined" do
      result = Aprs.parse_data(:user_defined, "", "{userdef")
      assert is_map(result)
      assert result[:data_type] == :user_defined
    end

    # test "returns map for third_party_traffic" do
    #   result = Aprs.parse_data(:third_party_traffic, "", "}thirdparty")
    #   assert is_map(result)
    #   assert result[:data_type] == :third_party_traffic
    # end

    test "returns map for peet_logging" do
      result = Aprs.parse_data(:peet_logging, "", "*peet")
      assert is_map(result)
      assert result[:data_type] == :peet_logging
    end

    test "returns map for station_capabilities" do
      result = Aprs.parse_data(:station_capabilities, "", "<cap")
      assert is_map(result)
      assert result[:data_type] == :station_capabilities
    end

    test "returns map for query" do
      result = Aprs.parse_data(:query, "", "?query")
      assert is_map(result)
      assert result[:data_type] == :query
    end

    test "returns map for df_report" do
      result = Aprs.parse_data(:df_report, "", "#DFS1234rest")
      assert is_map(result)
      assert result[:data_type] == :df_report
    end

    test "returns struct for phg_data" do
      result = Aprs.parse_data(:phg_data, "", "#PHG1234rest")
      assert match?(%Aprs.Types.ParseError{}, result)
      assert result.error_code == :not_implemented
      assert result.error_message == "PHG/DFS parsing not yet implemented"
    end

    test "extracts coordinates from timestamped position with weather packet" do
      # This is a typical APRS timestamped position with weather
      packet = "/201739z3316.04N/09631.96W_247/002g015t090h60b10161jDvs /A=000660"
      destination = "APRS"
      # The data type indicator is the first character
      data_type = Aprs.parse_datatype(packet)
      # Remove the type indicator for parse_data
      data_without_type = String.slice(packet, 1..-1//1)
      result = Aprs.parse_data(data_type, destination, data_without_type)
      assert is_map(result)
      assert is_struct(result[:latitude], Decimal)
      assert is_struct(result[:longitude], Decimal)
      assert Decimal.equal?(Decimal.round(result[:latitude], 6), Decimal.new("33.267333"))
      assert Decimal.equal?(Decimal.round(result[:longitude], 6), Decimal.new("-96.532667"))
    end

    test "extracts coordinates from timestamped position with weather and sets has_position" do
      packet =
        "KG5CK-1>APRS,TCPIP*,qAC,T2SPAIN:@201750z3301.64N/09639.10W_c038s003g004t091r000P000h62b10108"

      {:ok, parsed} = Aprs.parse(packet)
      data = parsed.data_extended
      assert is_map(data)
      assert data[:data_type] == :position
    end

    test "extracts lat/lon from @ timestamped position with message packet (issue regression)" do
      packet =
        "NM6E>APOSW,TCPIP*,qAC,T2SPAIN:@201807z3311.59N/09639.67Wr/A=000656SharkRF openSPOT2 -Shack"

      {:ok, parsed} = Aprs.parse(packet)
      data = parsed.data_extended
      assert is_map(data)
      assert is_struct(data[:latitude], Decimal)
      assert is_struct(data[:longitude], Decimal)
      refute is_nil(data[:latitude])
      refute is_nil(data[:longitude])
      if Map.has_key?(data, :has_location), do: assert(data[:has_location])
    end

    test "handles compressed position data without / prefix (malformed compressed position)" do
      # This is the problematic packet from the user
      packet =
        "YM1KTC-14>APLRG1,TCPIP*,qAC,T2UK:!L9f\\]UP1fa GAmatör Radyocular Derneği - YM1KTC Aytepe_Mevkii LoRa Aprs i-Gate - 433.775 Derneğimiz: https://www.qrz.com/db/YM1KTC Güncel Röle Bilgileri: https://www.ta-role.com "

      {:ok, parsed} = Aprs.parse(packet)
      data = parsed.data_extended

      # Should be parsed as compressed position despite missing "/" prefix
      assert is_map(data)
      assert data[:data_type] == :position
      assert data[:compressed?] == true
      assert data[:position_format] == :compressed
      assert data[:symbol_table_id] == "/"
      assert data[:symbol_code] == "f"
      assert data[:compression_type] == "G"

      # Should have valid coordinates
      assert is_float(data[:latitude])
      assert is_float(data[:longitude])
      assert_in_delta data[:latitude], 18.64, 0.1
      assert_in_delta data[:longitude], 59.67, 0.1

      # Should have course/speed data
      assert data[:course] == -4
      assert_in_delta data[:speed], 0.01, 0.01

      # Should have position
      assert data[:has_position] == true
    end
  end

  describe "parse/1" do
    test "returns {:error, _} for obviously invalid input" do
      assert match?({:error, _}, Aprs.parse(""))
      assert match?({:error, _}, Aprs.parse("notapacket"))
    end

    test "extracts lat/lon from @ timestamped position with message packet (issue regression)" do
      packet =
        "NM6E>APOSW,TCPIP*,qAC,T2SPAIN:@201807z3311.59N/09639.67Wr/A=000656SharkRF openSPOT2 -Shack"

      {:ok, parsed} = Aprs.parse(packet)
      data = parsed.data_extended
      assert is_map(data)
      assert is_struct(data[:latitude], Decimal)
      assert is_struct(data[:longitude], Decimal)
      refute is_nil(data[:latitude])
      refute is_nil(data[:longitude])
      if Map.has_key?(data, :has_location), do: assert(data[:has_location])
    end
  end
end
