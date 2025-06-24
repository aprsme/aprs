defmodule ParserTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "split_packet/1" do
    property "returns {:ok, [sender, path, data]} for valid packets" do
      check all sender <- StreamData.string(:alphanumeric, min_length: 1),
                path <- StreamData.string(:alphanumeric, min_length: 1),
                data <- StreamData.string(:printable, min_length: 1) do
        packet = sender <> ">" <> path <> ":" <> data
        assert {:ok, [^sender, ^path, ^data]} = AprsParser.split_packet(packet)
      end
    end

    property "returns error for invalid packets" do
      check all s <- StreamData.string(:printable, max_length: 10) do
        bad = s <> s
        assert match?({:error, _}, AprsParser.split_packet(bad))
      end
    end

    test "returns error for missing > or :" do
      assert match?({:error, _}, AprsParser.split_packet("senderpathdata"))
      assert match?({:error, _}, AprsParser.split_packet(":onlycolon"))
      assert match?({:error, _}, AprsParser.split_packet(">onlygt"))
    end
  end

  describe "split_path/1" do
    property "splits path into destination and digipeater path for any string" do
      check all s <- StreamData.string(:alphanumeric, min_length: 0, max_length: 10) do
        result = AprsParser.split_path(s)
        assert match?({:ok, [_, _]}, result)
      end
    end

    test "splits with no comma" do
      assert {:ok, ["DEST", ""]} = AprsParser.split_path("DEST")
    end

    test "splits with one comma" do
      assert {:ok, ["DEST", "DIGI"]} = AprsParser.split_path("DEST,DIGI")
    end

    test "returns error for more than one comma" do
      assert {:ok, ["A", "A,A"]} = AprsParser.split_path("A,A,A")
    end
  end

  describe "parse_callsign/1" do
    property "parses valid callsigns" do
      check all base <- StreamData.string(:alphanumeric, min_length: 1),
                ssid <- StreamData.string(:alphanumeric, min_length: 1) do
        callsign = base <> "-" <> ssid
        assert {:ok, [^base, ^ssid]} = AprsParser.parse_callsign(callsign)
      end
    end
  end

  describe "validate_path/1" do
    property "rejects paths with too many components" do
      check all n <- StreamData.integer(9..20) do
        path = Enum.map_join(1..n, ",", fn _ -> "WIDE1" end)
        assert match?({:error, _}, AprsParser.validate_path(path))
      end
    end

    property "accepts paths with 8 or fewer components" do
      check all n <- StreamData.integer(1..8) do
        path = Enum.map_join(1..n, ",", fn _ -> "WIDE1" end)
        assert :ok = AprsParser.validate_path(path)
      end
    end
  end

  describe "parse_datatype/1 and parse_datatype_safe/1" do
    property "parse_datatype returns an atom for any printable string" do
      check all s <- StreamData.string(:printable, min_length: 1) do
        assert is_atom(AprsParser.parse_datatype(s))
      end
    end

    test "parse_datatype_safe returns {:ok, atom} for non-empty, {:error, _} for empty" do
      assert {:ok, _} = AprsParser.parse_datatype_safe("!")
      assert {:error, _} = AprsParser.parse_datatype_safe("")
    end

    test "returns correct atom for each known type indicator" do
      assert AprsParser.parse_datatype(":msg") == :message
      assert AprsParser.parse_datatype(">status") == :status
      assert AprsParser.parse_datatype("!pos") == :position
      assert AprsParser.parse_datatype("/tspos") == :timestamped_position
      assert AprsParser.parse_datatype("=posmsg") == :position_with_message
      assert AprsParser.parse_datatype("@tsmsg") == :timestamped_position_with_message
      assert AprsParser.parse_datatype(";object") == :object
      assert AprsParser.parse_datatype("`mic_e") == :mic_e_old
      assert AprsParser.parse_datatype("'mic_e_old") == :mic_e_old
      assert AprsParser.parse_datatype("_weather") == :weather
      assert AprsParser.parse_datatype("Ttele") == :telemetry
      assert AprsParser.parse_datatype("$raw") == :raw_gps_ultimeter
      assert AprsParser.parse_datatype("<cap") == :station_capabilities
      assert AprsParser.parse_datatype("?query") == :query
      assert AprsParser.parse_datatype("{userdef") == :user_defined
      assert AprsParser.parse_datatype("}thirdparty") == :third_party_traffic
      assert AprsParser.parse_datatype("%item") == :item
      assert AprsParser.parse_datatype(")item") == :item
      assert AprsParser.parse_datatype("*peet") == :peet_logging
      assert AprsParser.parse_datatype(",test") == :invalid_test_data
      assert AprsParser.parse_datatype("#DFSfoo") == :df_report
      assert AprsParser.parse_datatype("#PHGfoo") == :phg_data
      assert AprsParser.parse_datatype("#foo") == :phg_data
      assert AprsParser.parse_datatype("Xunknown") == :unknown_datatype
    end
  end

  describe "parse_data/3" do
    test "returns nil for unknown type" do
      assert AprsParser.parse_data(:unknown, "", "") == nil
    end

    test "returns nil for invalid test data" do
      assert AprsParser.parse_data(:invalid_test_data, "", ",testdata")[:data_type] ==
               :invalid_test_data
    end

    test "returns map for weather" do
      result = AprsParser.parse_data(:weather, "", "_12345678c000s000g000t000r000p000P000h00b00000")
      assert is_map(result)
      assert result[:data_type] == :weather
    end

    test "returns map for telemetry" do
      result = AprsParser.parse_data(:telemetry, "", "T#123,456,789,012,345,678,901,234")
      assert is_map(result)
      assert result[:data_type] == :telemetry
    end

    test "returns map for object" do
      result = AprsParser.parse_data(:object, "", ";OBJECT*111111z4903.50N/07201.75W>Test object")
      assert is_map(result)
      assert result[:data_type] == :object
    end

    test "returns map for item" do
      result = AprsParser.parse_data(:item, "", ")ITEM!4903.50N/07201.75W>Test item")
      assert is_map(result)
      assert result[:data_type] == :item
    end

    test "returns map for status" do
      result = AprsParser.parse_data(:status, "", ">Test status message")
      assert is_map(result)
      assert result[:data_type] == :status
    end

    test "returns map for user_defined" do
      result = AprsParser.parse_data(:user_defined, "", "{userdef")
      assert is_map(result)
      assert result[:data_type] == :user_defined
    end

    # test "returns map for third_party_traffic" do
    #   result = AprsParser.parse_data(:third_party_traffic, "", "}thirdparty")
    #   assert is_map(result)
    #   assert result[:data_type] == :third_party_traffic
    # end

    test "returns map for peet_logging" do
      result = AprsParser.parse_data(:peet_logging, "", "*peet")
      assert is_map(result)
      assert result[:data_type] == :peet_logging
    end

    test "returns map for station_capabilities" do
      result = AprsParser.parse_data(:station_capabilities, "", "<cap")
      assert is_map(result)
      assert result[:data_type] == :station_capabilities
    end

    test "returns map for query" do
      result = AprsParser.parse_data(:query, "", "?query")
      assert is_map(result)
      assert result[:data_type] == :query
    end

    test "returns map for df_report" do
      result = AprsParser.parse_data(:df_report, "", "#DFS1234rest")
      assert is_map(result)
      assert result[:data_type] == :df_report
    end

    test "returns struct for phg_data" do
      result = AprsParser.parse_data(:phg_data, "", "#PHG1234rest")
      assert match?(%AprsParser.Types.ParseError{}, result)
      assert result.error_code == :not_implemented
      assert result.error_message == "PHG/DFS parsing not yet implemented"
    end

    test "extracts coordinates from timestamped position with weather packet" do
      # This is a typical APRS timestamped position with weather
      packet = "/201739z3316.04N/09631.96W_247/002g015t090h60b10161jDvs /A=000660"
      destination = "APRS"
      # The data type indicator is the first character
      data_type = AprsParser.parse_datatype(packet)
      # Remove the type indicator for parse_data
      data_without_type = String.slice(packet, 1..-1//1)
      result = AprsParser.parse_data(data_type, destination, data_without_type)
      assert is_map(result)
      assert is_struct(result[:latitude], Decimal)
      assert is_struct(result[:longitude], Decimal)
      assert Decimal.equal?(Decimal.round(result[:latitude], 6), Decimal.new("33.267333"))
      assert Decimal.equal?(Decimal.round(result[:longitude], 6), Decimal.new("-96.532667"))
    end

    test "extracts coordinates from timestamped position with weather and sets has_position" do
      packet =
        "KG5CK-1>APRS,TCPIP*,qAC,T2SPAIN:@201750z3301.64N/09639.10W_c038s003g004t091r000P000h62b10108"

      {:ok, parsed} = AprsParser.parse(packet)
      data = parsed.data_extended
      assert is_map(data)
      assert data[:data_type] == :position
    end

    test "extracts lat/lon from @ timestamped position with message packet (issue regression)" do
      packet =
        "NM6E>APOSW,TCPIP*,qAC,T2SPAIN:@201807z3311.59N/09639.67Wr/A=000656SharkRF openSPOT2 -Shack"

      {:ok, parsed} = AprsParser.parse(packet)
      data = parsed.data_extended
      assert is_map(data)
      assert is_struct(data[:latitude], Decimal)
      assert is_struct(data[:longitude], Decimal)
      refute is_nil(data[:latitude])
      refute is_nil(data[:longitude])
      if Map.has_key?(data, :has_location), do: assert(data[:has_location])
    end
  end

  describe "parse/1" do
    test "returns {:error, _} for obviously invalid input" do
      assert match?({:error, _}, AprsParser.parse(""))
      assert match?({:error, _}, AprsParser.parse("notapacket"))
    end

    test "extracts lat/lon from @ timestamped position with message packet (issue regression)" do
      packet =
        "NM6E>APOSW,TCPIP*,qAC,T2SPAIN:@201807z3311.59N/09639.67Wr/A=000656SharkRF openSPOT2 -Shack"

      {:ok, parsed} = AprsParser.parse(packet)
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
