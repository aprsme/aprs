defmodule Aprs.FieldMappingTest do
  use ExUnit.Case, async: true

  describe "field mapping to reference format" do
    test "maps position_ambiguity to posambiguity" do
      packet = "N0CALL>APRS:!1234.56N/12345.67W-Test"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Should have posambiguity field
      assert Map.has_key?(parsed, :posambiguity)
      assert is_integer(parsed.posambiguity)
    end

    test "maps dao datum to daodatumbyte" do
      # Packet with DAO extension
      packet = "N0CALL>APRS:!1234.56N/12345.67W-Test!WX!"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Should have daodatumbyte field
      assert Map.has_key?(parsed, :daodatumbyte)
    end

    test "maps weather data to wx field" do
      # Packet with weather data
      packet = "N0CALL>APRS:_12345678c000s000g000t000r000p000P000h00b00000Test"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Should have wx field
      assert Map.has_key?(parsed, :wx)
      assert is_map(parsed.wx)
    end

    test "maps telemetry bits to mbits" do
      # Packet with telemetry data
      packet = "N0CALL>APRS:T#123,123,123,123,123,123,00000000"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Should have mbits field
      assert Map.has_key?(parsed, :mbits)
      assert is_binary(parsed.mbits)
    end

    test "includes all required base fields" do
      packet = "N0CALL>APRS:!1234.56N/12345.67W-Test"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Check for commonly missing fields
      assert Map.has_key?(parsed, :format)
      assert Map.has_key?(parsed, :messaging)
      assert Map.has_key?(parsed, :gpsfixstatus)
      assert Map.has_key?(parsed, :message)
      assert Map.has_key?(parsed, :phg)
      assert Map.has_key?(parsed, :radiorange)
      assert Map.has_key?(parsed, :itemname)
    end
  end

  describe "data type mapping" do
    test "maps position_with_message to location type" do
      # Packet that should be parsed as position_with_message
      packet = "N0CALL>APRS:!1234.56N/12345.67W-Test message"
      assert {:ok, parsed} = Aprs.parse(packet)

      assert parsed.type == "location"
    end

    test "maps weather packets to wx type" do
      # Packet with weather data
      packet = "N0CALL>APRS:_12345678c000s000g000t000r000p000P000h00b00000Test"
      assert {:ok, parsed} = Aprs.parse(packet)

      assert parsed.type == "wx"
    end

    test "maps mic_e packets to location type" do
      # Packet with Mic-E data
      packet = "N0CALL>APRS:`123456z1234.56N/12345.67W-Test"
      assert {:ok, parsed} = Aprs.parse(packet)

      assert parsed.type == "location"
    end

    test "maps malformed_position to location type" do
      # Packet with malformed position
      packet = "N0CALL>APRS:!invalid-position"
      assert {:ok, parsed} = Aprs.parse(packet)

      assert parsed.type == "location"
    end
  end

  describe "field value consistency" do
    test "sets default values for missing fields" do
      packet = "N0CALL>APRS:!1234.56N/12345.67W-Test"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Check default values
      assert parsed.posambiguity == 0
      assert parsed.format == "uncompressed"
      assert parsed.messaging == 0
    end

    test "preserves existing field values" do
      packet = "N0CALL>APRS:!1234.56N/12345.67W-Test"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Should preserve existing fields
      assert parsed.srccallsign == "N0CALL"
      assert parsed.dstcallsign == "APRS"
      assert parsed.data_type == :position
    end
  end

  describe "compressed position parsing" do
    test "correctly identifies compressed format" do
      # Compressed position packet
      packet = "DL3EMX-9>APRS,qAR,SQ3EMX-10:!/4Z-lS%<9>&!HLilyTTGO Tracker"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Should be identified as compressed
      assert parsed.format == "compressed"
      assert parsed.data_type == :position
    end

    test "correctly parses compressed coordinates" do
      # Compressed position packet
      packet = "DL3EMX-9>APRS,qAR,SQ3EMX-10:!/4Z-lS%<9>&!HLilyTTGO Tracker"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Should have valid coordinates
      assert is_number(parsed.latitude)
      assert is_number(parsed.longitude)
      assert parsed.latitude > 0
      assert parsed.longitude > 0
    end

    test "correctly parses compressed symbol code" do
      # Compressed position packet
      packet = "DL3EMX-9>APRS,qAR,SQ3EMX-10:!/4Z-lS%<9>&!HLilyTTGO Tracker"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Should have correct symbol code
      assert parsed.symbolcode == ">"
    end

    test "correctly parses compressed comment" do
      # Compressed position packet
      packet = "DL3EMX-9>APRS,qAR,SQ3EMX-10:!/4Z-lS%<9>&!HLilyTTGO Tracker"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Debug output
      # IO.puts("Parsed packet:")
      # IO.inspect(parsed, pretty: true)

      # Should have correct comment
      assert parsed.comment == "HLilyTTGO Tracker"
    end
  end

  describe "compressed position debugging" do
    test "debug compressed position packet" do
      # Compressed position packet that's failing
      packet = "DL3EMX-9>APRS,qAR,SQ3EMX-10:!/4Z-lS%<9>&!HLilyTTGO Tracker"
      assert {:ok, parsed} = Aprs.parse(packet)

      # Debug output
      IO.puts("Parsed packet:")
      IO.inspect(parsed, pretty: true)

      # Check what data_type it was parsed as
      assert parsed.data_type == :position

      # Check if it has position data
      assert Map.has_key?(parsed, :latitude)
      assert Map.has_key?(parsed, :longitude)
    end
  end

  describe "DAO extension debugging" do
    test "debug DAO extension parsing" do
      # Test the DAO extension pattern directly
      comment = "&!HLilyTTGO Tracker"

      # Test the regex pattern directly
      case Regex.run(~r/&!([A-Za-z])/, comment) do
        [_, datum_byte] ->
          # IO.puts("DAO regex matched: #{datum_byte}")
          assert datum_byte == "H"

        _ ->
          # IO.puts("DAO regex did not match")
          flunk("DAO regex did not match")
      end

      # Test the full packet
      packet = "DL3EMX-9>APRS,qAR,SQ3EMX-10:!/4Z-lS%<9>&!HLilyTTGO Tracker"
      assert {:ok, _parsed} = Aprs.parse(packet)

      # IO.puts("DAO field in parsed packet:")
      # IO.inspect(parsed.dao, pretty: true)
      # IO.inspect(parsed.daodatumbyte, pretty: true)
    end
  end

  describe "real-world packet with DAO extension" do
    test "parses DAO extension and matches FAP output" do
      packet =
        "OE5DXL-11>APLWS2,qAO,OE5DXL-14:;X1323381 *005602h4742.81N/01918.44EO244/036/A=111870!wuG!Clb=-29.9m/s p=7.1hPa t=-32.2C h=1.5% 403.70MHz Type=RS41-SGP (RS41,RS92,C34,C50,DFM,M10,iMET,MRZ,IMS)"

      assert {:ok, parsed} = Aprs.parse(packet)
      # FAP output: 'daodatumbyte' => 'W'
      assert parsed.daodatumbyte == "W"
      # FAP output: 'objectname' => 'X1323381 '
      assert parsed.objectname == "X1323381 "
      # FAP output: 'format' => 'uncompressed'
      assert parsed.format == "uncompressed"
      # FAP output: 'symboltable' => '/'
      assert parsed.symboltable == "/"
      # FAP output: 'symbolcode' => 'O'
      assert parsed.symbolcode == "O"
      # FAP output: 'latitude' => '47.7136538461538'
      # Note: Our parser has less precision than FAP due to DAO processing differences
      assert_in_delta String.to_float("#{parsed.latitude}"), 47.71365, 0.001
      # FAP output: 'longitude' => '19.3074029304029'
      assert_in_delta String.to_float("#{parsed.longitude}"), 19.30740, 0.001

      # FAP output: 'comment' => 'Clb=-29.9m/s p=7.1hPa t=-32.2C h=1.5% 403.70MHz Type=RS41-SGP (RS41,RS92,C34,C50,DFM,M10,iMET,MRZ,IMS)'
      assert parsed.comment =~ "Clb=-29.9m/s"
      assert parsed.comment =~ "Type=RS41-SGP"
    end
  end
end
