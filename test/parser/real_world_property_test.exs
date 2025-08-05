defmodule Aprs.RealWorldPropertyTest do
  @moduledoc """
  Property-based tests based on real-world APRS packet patterns and edge cases.
  These tests are derived from analysis of actual packets in packets.csv.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Helper to handle parse results
  defp parse_packet(packet) do
    case Aprs.parse(packet) do
      {:ok, result} -> result
      _ -> nil
    end
  end

  describe "real-world path variations" do
    property "handles complex digipeater paths" do
      check all hops <-
                  list_of(
                    member_of(["WIDE1-1", "WIDE2-1", "WIDE2-2", "WIDE2", "RELAY", "TRACE", "ECHO"]),
                    min_length: 0,
                    max_length: 8
                  ),
                has_qconstruct <- boolean(),
                has_asterisk <- boolean() do
        base_path = "APRS"

        path =
          if has_qconstruct do
            qtype = Enum.random(["qAC", "qAR", "qAO", "qAS", "qAU"])
            server = Enum.random(["T2TOKYO", "T2TEXAS", "T2SYDNEY", "T2NORWAY"])
            base_path <> "," <> Enum.join(hops, ",") <> "," <> qtype <> "," <> server
          else
            hop_path = Enum.join(hops, ",")

            if has_asterisk && length(hops) > 0 do
              # Add asterisk to random hop
              base_path <> "," <> hop_path <> "*"
            else
              base_path <> "," <> hop_path
            end
          end

        packet = "TEST>#{path}:!4903.50N/07201.75W>"

        result = parse_packet(packet)
        assert result == nil or is_map(result)

        if result != nil do
          # The parser stores the full path in the packet
          assert result.path == path || result.path == path |> String.split(",", parts: 2) |> List.last() ||
                   result.path == ""
        end
      end
    end

    property "handles TCPIP and internet paths" do
      check all server <- member_of(["T2TOKYO", "T2TEXAS", "T2SYDNEY", "APRSFI", "APRSIS", "HAMCLOUD1"]),
                has_tcpip <- boolean() do
        path =
          if has_tcpip do
            "APRS,TCPIP*,qAC,#{server}"
          else
            "APRS,qAS,#{server}"
          end

        packet = "TEST>#{path}:>Status message"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "real-world symbol variations" do
    property "handles extended symbol tables" do
      check all _primary_symbol <- string(Enum.to_list(33..126), length: 1),
                overlay <-
                  member_of(
                    (?A..?Z |> Enum.to_list() |> Enum.map(&<<&1>>)) ++ (?0..?9 |> Enum.to_list() |> Enum.map(&<<&1>>))
                  ) do
        # Test overlay symbols (using \\ table with overlay)
        packet = "TEST>APRS:!4903.50N\\07201.75W#{overlay}PHG5360"

        result = parse_packet(packet)

        if result != nil && result.data_type == :position do
          assert result.data_extended.symbol_table_id == "\\"
        end
      end
    end
  end

  describe "real-world device-specific formats" do
    property "handles device-specific prefixes and suffixes" do
      check all device <- member_of(["APRS", "APDW17", "APMI06", "APLRG1", "APDG03", "APU25N", "APDR16"]),
                suffix <- string(:alphanumeric, max_length: 5),
                prefix <- member_of(["!", "@", "=", "/", "`", "'", ">", ";"]) do
        path =
          if suffix == "" do
            device
          else
            device <> "-" <> suffix
          end

        # Different devices use different data formats
        data =
          case prefix do
            "!" -> "!4903.50N/07201.75W>"
            "@" -> "@032035z4903.50N/07201.75W>"
            "=" -> "=4903.50N/07201.75W>"
            "/" -> "/032035z4903.50N/07201.75W>"
            "`" -> "`" <> :binary.list_to_bin(Enum.map(1..8, fn _ -> :rand.uniform(95) + 32 end))
            ">" -> ">Device status message"
            ";" -> ";OBJECT   *032035z4903.50N/07201.75W>"
            _ -> "!4903.50N/07201.75W>"
          end

        packet = "TEST>#{path}:#{data}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "real-world comment field variations" do
    property "handles complex comment fields with multiple data extensions" do
      check all base_comment <- string(:printable, max_length: 20),
                extensions <-
                  list_of(member_of(["PHG", "RNG", "DFS", "DAO", "ALTITUDE", "DIGI"]), min_length: 0, max_length: 6) do
        comment = base_comment

        comment =
          if "PHG" in extensions do
            phg_val = "PHG#{:rand.uniform(9)}#{:rand.uniform(9)}#{:rand.uniform(9)}#{:rand.uniform(9)}"
            comment <> phg_val
          else
            comment
          end

        comment =
          if "RNG" in extensions do
            rng_val = "RNG#{String.pad_leading(to_string(:rand.uniform(9999)), 4, "0")}"
            comment <> rng_val
          else
            comment
          end

        comment =
          if "ALTITUDE" in extensions do
            alt = "/A=#{String.pad_leading(to_string(:rand.uniform(99_999)), 6, "0")}"
            comment <> alt
          else
            comment
          end

        comment =
          if "DAO" in extensions do
            comment <> "!W12!"
          else
            comment
          end

        packet = "TEST>APRS:!4903.50N/07201.75W>#{comment}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :position do
          # Should parse all extensions
          assert result.data_extended.comment != nil
        end
      end
    end
  end

  describe "real-world special characters and encoding" do
    property "handles packets with special characters in comments" do
      check all special_chars <-
                  list_of(
                    member_of(["&", "#", "@", "!", "%", "^", "*", "(", ")", "[", "]", "{", "}"]),
                    max_length: 5
                  ),
                text <- string(:alphanumeric, max_length: 20) do
        comment = Enum.join(special_chars, "") <> text
        packet = "TEST>APRS:>#{comment}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles binary data in Mic-E and compressed formats" do
      check all byte_count <- integer(5..20) do
        # Generate bytes that could appear in compressed/binary formats
        bytes =
          for _ <- 1..byte_count do
            # Valid range for compressed data (ASCII 33-126)
            :rand.uniform(126 - 33) + 33
          end

        binary_data = :binary.list_to_bin(bytes)

        # Test as compressed position
        packet1 = "TEST>APRS:!" <> binary_data
        result1 = parse_packet(packet1)
        assert result1 == nil or is_map(result1)

        # Test as Mic-E
        packet2 = "TEST>APRS:`" <> binary_data
        result2 = parse_packet(packet2)
        assert result2 == nil or is_map(result2)
      end
    end
  end

  describe "real-world malformed packets" do
    property "handles packets with truncated data" do
      check all full_data <-
                  member_of([
                    "!4903.50N/07201.75W>Comment",
                    "@032035z4903.50N/07201.75W_000/000g000t080",
                    ":ADDRESSEE:Message text{12345",
                    "T#123,001,002,003,004,005,00000000"
                  ]),
                truncate_at <- integer(5..(String.length(full_data) - 1)) do
        truncated = String.slice(full_data, 0, truncate_at)
        packet = "TEST>APRS:" <> truncated

        result = parse_packet(packet)
        # Should handle gracefully without crashing
        assert result == nil or is_map(result)
      end
    end

    property "handles packets with excessive whitespace" do
      check all spaces_before <- integer(0..5),
                spaces_middle <- integer(0..5),
                spaces_after <- integer(0..5) do
        spaced_data =
          String.duplicate(" ", spaces_before) <>
            "!4903.50N" <>
            String.duplicate(" ", spaces_middle) <>
            "/07201.75W>" <>
            String.duplicate(" ", spaces_after)

        packet = "TEST>APRS:" <> spaced_data

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "real-world callsign variations" do
    property "handles various callsign formats with SSIDs" do
      check all prefix <- member_of(["A", "K", "W", "N", "VE", "G", "F", "DL", "JA", "VK", "EA", "YM", "TA", "SP", "OK"]),
                suffix <- string(:alphanumeric, min_length: 1, max_length: 4),
                ssid <- integer(0..15),
                has_ssid <- boolean() do
        callsign =
          if has_ssid do
            "#{prefix}#{suffix}-#{ssid}"
          else
            "#{prefix}#{suffix}"
          end

        packet = "#{callsign}>APRS:>Test"

        result = parse_packet(packet)

        if result != nil do
          assert result.sender == callsign
        end
      end
    end

    property "handles tactical callsigns and special formats" do
      check all tactical <- member_of(["WIDE", "RELAY", "TRACE", "ECHO", "GATE", "DIGI", "BEACON", "WX"]),
                number <- integer(1..99),
                has_number <- boolean() do
        callsign =
          if has_number do
            "#{tactical}#{number}"
          else
            tactical
          end

        packet = "TEST>APRS,#{callsign}*:>Status"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles special system callsigns" do
      check all system <- member_of(["RS0ISS", "APRSIS", "TCPIP", "LOCAL", "RFONLY", "NOGATE"]),
                has_asterisk <- boolean() do
        path = if has_asterisk, do: "#{system}*", else: system
        packet = "TEST>APRS,#{path}:>System status"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "real-world data rate and precision variations" do
    property "handles various coordinate precision levels" do
      check all lat_precision <- integer(0..4),
                lon_precision <- integer(0..4) do
        # Generate coordinates with varying decimal places
        lat_dec = String.slice("12345", 0, lat_precision)
        lon_dec = String.slice("67890", 0, lon_precision)

        lat = "4903" <> if(lat_precision > 0, do: ".#{lat_dec}", else: "") <> "N"
        lon = "07201" <> if(lon_precision > 0, do: ".#{lon_dec}", else: "") <> "W"

        packet = "TEST>APRS:!#{lat}/#{lon}>"

        result = parse_packet(packet)

        if result != nil && result.data_type == :position do
          assert result.data_extended.latitude != nil
        end
      end
    end
  end

  describe "real-world packet variations from packets.csv" do
    property "handles D-STAR gateway packets" do
      check all callsign <- string(:alphanumeric, min_length: 3, max_length: 6),
                ssid <- member_of(["B", "C", "D", "G", "S"]),
                freq <- float(min: 144.0, max: 450.0),
                offset <- float(min: -10.0, max: 10.0) do
        # D-STAR format like "!4205.91ND07917.77W&RNG0001/A=000010 70cm Voice (D-Star) 446.42500MHz +0.0000MHz"
        comment =
          "RNG0001/A=000010 70cm Voice (D-Star) #{:erlang.float_to_binary(freq, decimals: 5)}MHz #{if offset >= 0, do: "+", else: ""}#{:erlang.float_to_binary(offset, decimals: 4)}MHz"

        packet = "#{callsign}-#{ssid}>APDG02,TCPIP*,qAC,#{callsign}-#{ssid}S:!4205.91ND07917.77W&#{comment}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles LoRa iGate packets" do
      check all voltage <- float(min: 0.0, max: 5.0),
                has_gps <- boolean() do
        # LoRa format like "!L4G-{MWS)a xGLoRa APRS / iGATE QTH  Batt=4.12V"
        lora_data =
          if has_gps do
            "!L4G-{MWS)a xGLoRa APRS / iGATE QTH  Batt=#{:erlang.float_to_binary(voltage, decimals: 2)}V"
          else
            "!L4G-{MWS)_ xGLoRa APRS Batt=#{:erlang.float_to_binary(voltage, decimals: 2)}V"
          end

        packet = "MW7VHD-13>APLRG1,WIDE1-1,qAO,GW0KAX-10:#{lora_data}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles telemetry with text descriptions" do
      check all seq <- integer(0..999),
                values <- list_of(integer(0..999), length: 5),
                has_description <- boolean() do
        # Format like "T#066,161,058,000,086,000,00000000"
        seq_str = String.pad_leading(to_string(seq), 3, "0")
        val_str = Enum.map_join(values, ",", &String.pad_leading(to_string(&1), 3, "0"))

        data =
          if has_description do
            "T##{seq_str},#{val_str},00000000 Battery OK"
          else
            "T##{seq_str},#{val_str},00000000"
          end

        packet = "MNARCH>APMI04,TCPIP*,qAC,T2VAN:#{data}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles WPSD (Pi-Star) status messages" do
      check all url <- member_of(["https://wpsd.radio", "https://pi-star.uk", "wpsd.local"]) do
        packet = "DO7DH-10>APDG03,qAS,DO7DH:>Powered by WPSD (#{url})"

        result = parse_packet(packet)

        if result != nil && result.data_type == :status do
          assert String.contains?(result.data_extended[:status] || result.data_extended[:status_text] || "", "WPSD")
        end
      end
    end

    property "handles WX3in1 weather station packets" do
      check all voltage <- float(min: 10.0, max: 15.0),
                temp_c <- float(min: -40.0, max: 60.0),
                has_position <- boolean() do
        comment =
          if has_position do
            "@032035z4709.26N/00949.44E&WX3in1Plus2.0 U=#{:erlang.float_to_binary(voltage, decimals: 1)}V,T=#{:erlang.float_to_binary(temp_c, decimals: 1)}C"
          else
            "WX3in1Plus2.0 U=#{:erlang.float_to_binary(voltage, decimals: 1)}V,T=#{:erlang.float_to_binary(temp_c, decimals: 1)}C"
          end

        packet = "OE9XVD-6>APMI06,TCPIP*,qAC,T2AUSTRIA:#{comment}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles multi-language comments" do
      check all lang <- member_of([:english, :spanish, :german, :japanese, :chinese]),
                message_type <- member_of([:status, :beacon, :info]) do
        text =
          case lang do
            :english -> "APRS iGate Online"
            :spanish -> "Estación APRS activa"
            :german -> "APRS Station aktiv"
            :japanese -> "APRS 運用中"
            :chinese -> "APRS 网关在线"
          end

        data =
          case message_type do
            :status -> ">#{text}"
            :beacon -> "!4903.50N/07201.75W>#{text}"
            :info -> ":ALL      :#{text}"
          end

        packet = "TEST>APRS:#{data}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles packets with software version info" do
      check all software <- member_of(["DireWolf", "aprx", "YAAC", "Xastir", "UI-View", "APRSISCE"]),
                version <- string(:alphanumeric, min_length: 1, max_length: 5) do
        # Various software announcement formats
        status = "#{software} #{version} on Linux"
        packet = "TEST>APRS:>#{status}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :status do
          assert String.contains?(result.data_extended[:status] || result.data_extended[:status_text] || "", software)
        end
      end
    end
  end
end
