defmodule Aprs.CompressedPositionWithTelemetryTest do
  use ExUnit.Case, async: true

  describe "compressed position packets with embedded telemetry" do
    test "parses compressed position with embedded telemetry in comment" do
      packet = "EA2TU-10>APLRG1,TCPIP*,qAC,T2BC:!L8O#dMWQs#  GLoRa_APRS_iGate@EA2TU_Isla Playa|%g%\\!H|"
      {:ok, parsed} = Aprs.parse(packet)

      # Check basic fields
      assert parsed.sender == "EA2TU-10"
      assert parsed.destination == "APLRG1"
      assert parsed.data_type == :position

      # Check position data
      data = parsed.data_extended
      assert data.compressed? == true
      assert data.symbol_table_id == "L"
      assert data.symbol_code == "#"
      assert data.format == :compressed
      assert data.position_ambiguity == 0

      assert data.compression_info == %{
               gps_fix: :current,
               nmea_source: :other,
               origin: :other_tracker
             }

      assert_in_delta data.latitude, 43.4993463297333, 0.0001
      assert_in_delta data.longitude, -3.54185327333917, 0.0001
      # cs and compression type bytes consumed per APRS compressed spec
      assert data.comment == "LoRa_APRS_iGate@EA2TU_Isla Playa"
      assert data.posresolution == 0.291

      # Check telemetry extraction
      assert data.telemetry
      assert data.telemetry.seq == 434
      assert data.telemetry.vals == [423, 39]
    end

    test "parses uncompressed position with course, speed, and altitude" do
      packet = "PU5PLR-5>APDR16,TCPIP*,qAC,T2PANAMA:=2319.61S/05107.94Wa072/031/A=001847 PU5PLR - Leonardo"
      {:ok, parsed} = Aprs.parse(packet)

      # Check basic fields
      assert parsed.sender == "PU5PLR-5"
      assert parsed.destination == "APDR16"
      assert parsed.data_type == :position_with_message

      # Check position data
      data = parsed.data_extended
      assert data.compressed? == false
      assert data.format == :uncompressed
      assert_in_delta data.latitude, -23.3268333333333, 0.0001
      assert_in_delta data.longitude, -51.1323333333333, 0.0001
      assert data.symbol_table_id == "/"
      assert data.symbol_code == "a"
      assert data.course == 72
      assert data.speed == 31.0
      assert data.altitude == 1847.0
      assert data.comment == "PU5PLR - Leonardo"
      assert data.position_ambiguity == 0
      assert data.posresolution == 18.52
      assert data.aprs_messaging? == true
    end

    test "parses telemetry data packet" do
      packet = "LU8FJH-10>APRX24,TCPIP*,qAC,T2SYDNEY:T#191,0.0,0.2,0.0,0.0,1.0,00000000"
      {:ok, parsed} = Aprs.parse(packet)

      # Check basic fields
      assert parsed.sender == "LU8FJH-10"
      assert parsed.destination == "APRX24"
      assert parsed.data_type == :telemetry

      # Check telemetry data
      data = parsed.data_extended
      assert data.data_type == :telemetry
      assert data.telemetry
      assert data.telemetry.seq == "191"
      assert data.telemetry.vals == [0.0, 0.2, 0.0, 0.0, 1.0]
      assert data.telemetry.bits == "00000000"
    end

    test "parses uncompressed position with embedded telemetry in comment" do
      packet = ~s(N0CALL>APRS,TCPIP*,qAC,T2TEST:!4903.50N/07201.75W-iGate |%g%\\!H|)
      {:ok, parsed} = Aprs.parse(packet)

      data = parsed.data_extended
      assert data.compressed? == false
      assert data.comment == "iGate"
      assert data.telemetry.seq == 434
      assert data.telemetry.vals == [423, 39]
    end

    test "parses timestamped position with embedded telemetry in comment" do
      packet = ~s(N0CALL>APRS,TCPIP*,qAC,T2TEST:@092345z4903.50N/07201.75W-iGate |%g%\\!H|)
      {:ok, parsed} = Aprs.parse(packet)

      data = parsed.data_extended
      assert data.comment == "iGate"
      assert data.telemetry.seq == 434
      assert data.telemetry.vals == [423, 39]
    end

    test "omits the telemetry key when the comment has none" do
      packet = "N0CALL>APRS,TCPIP*,qAC,T2TEST:!4903.50N/07201.75W-plain comment"
      {:ok, parsed} = Aprs.parse(packet)

      refute Map.has_key?(parsed.data_extended, :telemetry)
    end
  end
end
