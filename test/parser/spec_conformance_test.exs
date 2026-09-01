defmodule Aprs.SpecConformanceTest do
  @moduledoc """
  Packet-level regression tests for the parser audit against APRS 1.0.1 and the
  1.1/1.2 addenda.

  Each test pins one finding to the packet that exposed it, so a regression
  shows up at the `Aprs.parse/1` boundary rather than only inside a helper.
  """
  use ExUnit.Case, async: true

  defp parse!(packet) do
    {:ok, parsed} = Aprs.parse(packet)
    parsed
  end

  describe "compressed positions" do
    test "course comes from the c byte, speed from the s byte" do
      parsed = parse!("N0CALL>APRS:!/5L!!<*e7>7P[")

      assert parsed.course == 88
      assert_in_delta parsed.speed, 36.232, 0.001
      assert_in_delta parsed.latitude, 49.5, 0.001
      assert_in_delta parsed.longitude, -72.75, 0.001
    end

    test "the radio range form is signalled by { and carries no course or speed" do
      parsed = parse!("N0CALL>APRS:!/5L!!<*e7>{?[")

      assert_in_delta parsed.range, 20.0, 0.2
      refute Map.has_key?(parsed.data_extended, :course)
      refute Map.has_key?(parsed.data_extended, :speed)
    end

    test "Z is a course of 228, not a radio range" do
      parsed = parse!("N0CALL>APRS:!/5L!!<*e7>Z7[")

      assert parsed.course == 228
      refute Map.has_key?(parsed.data_extended, :range)
    end

    test "the compression type byte carries no ambiguity or messaging bits" do
      parsed = parse!("N0CALL>APRS:!/5L!!<*e7> sT")

      assert parsed.posambiguity == 0
      assert parsed.messaging == 0
      assert parsed.data_extended.compression_info == %{gps_fix: :current, nmea_source: :gga, origin: :tbd}
    end

    test "a GGA compression source puts altitude in the cs bytes" do
      parsed = parse!("N0CALL>APRS:!/5L!!<*e7>S]1")

      assert_in_delta parsed.altitude, 10_004.52, 0.01
      refute Map.has_key?(parsed.data_extended, :course)
    end

    test "spaces for cs and the compression type are a valid packet" do
      parsed = parse!("N0CALL>APRS:!/5L!!<*e7>   ")

      assert parsed.data_type == :position
      assert_in_delta parsed.latitude, 49.5, 0.001
    end
  end

  describe "Mic-E" do
    test "speed is knots and course is preserved" do
      parsed = parse!(~s(N0CALL>T7SYWU:`(_fn"Oj/))

      assert parsed.data_type == :mic_e
      assert parsed.speed == 20.0
      assert parsed.course == 251
    end

    test "a course of 360 means due north, not unknown" do
      parsed = parse!("N0CALL>T7SYWU:`(_fn)Xj/")

      assert parsed.course == 360
    end
  end

  describe "messages" do
    test "a numeric message number is split off the text" do
      parsed = parse!("N0CALL>APRS::WU2Z     :Testing{003")

      assert parsed.data_extended.message_text == "Testing"
      assert parsed.data_extended.message_number == "003"
    end

    test "a message number may be alphanumeric" do
      parsed = parse!("N0CALL>APRS::WU2Z     :Testing{AB1")

      assert parsed.data_extended.message_number == "AB1"
    end

    test "an ack is classified as an ack" do
      parsed = parse!("N0CALL>APRS::WU2Z     :ack003")

      assert parsed.data_type == :message_ack
      assert parsed.data_extended.messageack == "003"
      assert parsed.type == "messageack"
    end

    test "a rej is classified as a rej" do
      parsed = parse!("N0CALL>APRS::WU2Z     :rej003")

      assert parsed.data_type == :message_rej
      assert parsed.data_extended.messagerej == "003"
    end

    test "the reply-ack form gives both ids" do
      parsed = parse!("N0CALL>APRS::WU2Z     :hi{12}45")

      assert parsed.data_extended.message_text == "hi"
      assert parsed.data_extended.message_number == "12"
      assert parsed.data_extended.message_ack == "45"
    end

    test "a telemetry definition message is decoded" do
      parsed = parse!("N0CALL>APRS::N0CALL   :PARM.Battery,Temp,Light")

      assert parsed.data_type == :telemetry_message
      assert parsed.data_extended.parameter_names == ["Battery", "Temp", "Light"]
    end
  end

  describe "position format detection" do
    test "lower case hemisphere letters are an uncompressed position" do
      parsed = parse!("N0CALL>APRS:!4903.50n/07201.75w-Test")

      assert parsed.format == :uncompressed
      assert_in_delta parsed.latitude, 49.0583, 0.0001
      assert_in_delta parsed.longitude, -72.0292, 0.0001
    end

    test "a symbol table outside the compressed set is rejected" do
      parsed = parse!("N0CALL>APRS:!#5L!!<*e7>7P[")

      assert parsed.data_type == :position_error
      assert parsed.has_position == false
    end

    test "coordinates that decode out of range are rejected, not clamped" do
      parsed = parse!("N0CALL>APRS:!/~~~~~~~~>7P[")

      assert parsed.data_type == :position_error
      assert parsed.has_position == false
    end

    test "a position with no symbol code does not claim the weather symbol" do
      parsed = parse!("N0CALL>APRS:!4903.50N/07201.75W")

      assert parsed.symbol_code == nil
    end

    test "the poles and the antimeridian are valid" do
      parsed = parse!("N0CALL>APRS:!9000.00N/18000.00W-")

      assert parsed.latitude == 90.0
      assert parsed.longitude == -180.0
    end

    test "the legacy ! within the first 40 bytes is a position" do
      parsed = parse!("N0CALL>APRS:TEST!4903.50N/07201.75W-")

      assert parsed.data_type == :position
      assert_in_delta parsed.latitude, 49.0583, 0.0001
    end
  end

  describe "comment extensions" do
    test "DAO reports the datum byte and refines the coordinates" do
      parsed = parse!("N0CALL>APRS:!4903.50N/07201.75W-Test!W52!")

      assert parsed.daodatumbyte == "W"
      assert parsed.data_extended.comment == "Test"
      assert_in_delta parsed.latitude, 49.0 + 3.505 / 60, 1.0e-9
      assert_in_delta parsed.longitude, -(72.0 + 1.752 / 60), 1.0e-9
    end

    test "a DF signal report is parsed out of the comment" do
      parsed = parse!("N0CALL>APRS:!4903.50N\\07201.75W\\DFS2360/Test")

      assert parsed.data_extended.dfs == "2360"
      assert parsed.data_extended.comment == "Test"
    end

    test "a course/speed pair followed by BRG/NRQ is a DF report" do
      parsed = parse!("N0CALL>APRS:!4903.50N\\07201.75W\\088/036/270/729")

      assert parsed.course == 88
      assert parsed.data_extended.bearing == 270
      assert parsed.data_extended.nrq == "729"
    end
  end

  describe "objects, items and third party traffic" do
    test "an object timestamp ending in h is hours, minutes and seconds" do
      parsed = parse!("N0CALL>APRS:;LEADER   *120000h4903.50N/07201.75W>")
      today = Date.utc_today()
      {:ok, noon} = DateTime.new(today, ~T[12:00:00])

      assert parsed.timestamp == DateTime.to_unix(noon)
    end

    test "a compressed object on the alternate symbol table keeps its position" do
      parsed = parse!("N0CALL>APRS:;LEADER   *092345z\\5L!!<*e7>7P[Test")

      assert parsed.format == :compressed
      assert_in_delta parsed.latitude, 49.5, 0.001
      assert_in_delta parsed.longitude, -72.75, 0.001
    end

    test "an object keeps its RNG value" do
      parsed = parse!("N0CALL>APRS:;LEADER   *092345z4903.50N/07201.75W>RNG0050Test")

      assert parsed.radiorange == 50
    end

    test "a killed item reports alive 0 and its name" do
      parsed = parse!("N0CALL>APRS:)AID #2_4903.50N/07201.75WA")

      assert parsed.alive == 0
      assert parsed.itemname == "AID #2"
    end

    test "an item gets the same comment extensions as a position" do
      parsed = parse!("N0CALL>APRS:)AID #2!4903.50N/07201.75WA088/036/A=001234Test")

      assert parsed.course == 88
      assert parsed.speed == 36.0
      assert parsed.altitude == 1234.0
      assert parsed.data_extended.comment == "Test"
    end

    test "a tunnelled message keeps its data type indicator" do
      parsed = parse!("N0CALL>APRS:}W1ABC>APRS,TCPIP,IGATE*::WU2Z     :Hello{01")
      inner = parsed.data_extended.third_party_packet

      assert inner.data_type == :message
      assert inner.data_extended.addressee == "WU2Z"
      assert inner.data_extended.message_text == "Hello"
      assert inner.data_extended.message_number == "01"
    end
  end

  describe "weather, telemetry and NMEA" do
    test "a positionless report uses the eight digit timestamp and reads s as wind speed" do
      parsed = parse!("N0CALL>APRS:_10090556c220s004g005t077r000p000P000h50b09900wRSW")

      assert parsed.timestamp == "10090556"
      assert parsed.wind_speed == 4
      assert parsed.snow == nil
      assert parsed.temperature == 77
    end

    test "lower case l luminosity adds a thousand" do
      parsed = parse!("N0CALL>APRS:!4903.50N/07201.75W_l100")

      assert parsed.wx.luminosity == 1100
    end

    test "telemetry with three analog channels and no bits parses" do
      parsed = parse!("N0CALL>APRS:T#123,1,2,3")

      assert parsed.data_extended.telemetry == %{seq: "123", vals: [1.0, 2.0, 3.0], bits: nil}
    end

    test "a GN talker RMC sentence parses" do
      parsed = parse!("N0CALL>APRS:$GNRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W")

      assert parsed.data_extended.nmea_type == :rmc
      assert_in_delta parsed.latitude, 48.1173, 0.0001
      assert parsed.speed == 22.4
    end
  end

  describe "packet framing" do
    test "invalid bytes are repaired without losing the valid ones" do
      parsed = parse!("N0CALL>APRS:>Gr" <> <<0xC3, 0xBC>> <> "\u00dfe" <> <<0xFF>>)

      assert parsed.status_text == "Grüßeÿ"
    end

    test "every digipeater at or before the last * is marked used" do
      parsed = parse!("N0CALL>APRS,WIDE1-1,WIDE2*:>hi")

      assert parsed.digipeaters == [
               %{call: "WIDE1-1", wasdigied: 1},
               %{call: "WIDE2", wasdigied: 1}
             ]
    end

    test "a path with an empty element is rejected" do
      assert {:error, :invalid_packet} = Aprs.parse("N0CALL>APRS,,WIDE2-1:>hi")
    end

    test "a local time timestamp is accepted" do
      parsed = parse!("N0CALL>APRS:/092345/4903.50N/07201.75W>Test")

      assert is_integer(parsed.timestamp)
    end
  end
end
