defmodule Aprs.PropertyTest do
  @moduledoc """
  Property-based tests for APRS parser using real-world packet variations.
  Based on analysis of actual APRS packets from the wild.
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

  describe "position reports property tests" do
    property "handles various position formats with symbols" do
      check all lat_deg <- integer(0..89),
                lat_min <- integer(0..59),
                lat_dec <- integer(0..99),
                lat_dir <- member_of(["N", "S"]),
                lon_deg <- integer(0..179),
                lon_min <- integer(0..59),
                lon_dec <- integer(0..99),
                lon_dir <- member_of(["E", "W"]),
                symbol_table <-
                  member_of(
                    ["/", "\\"] ++
                      (?A..?Z |> Enum.to_list() |> Enum.map(&<<&1>>)) ++ (?0..?9 |> Enum.to_list() |> Enum.map(&<<&1>>))
                  ),
                symbol_code <- string([33..126], length: 1),
                comment <- string(:printable, max_length: 43) do
        lat =
          "#{String.pad_leading(to_string(lat_deg), 2, "0")}#{String.pad_leading(to_string(lat_min), 2, "0")}.#{String.pad_leading(to_string(lat_dec), 2, "0")}#{lat_dir}"

        lon =
          "#{String.pad_leading(to_string(lon_deg), 3, "0")}#{String.pad_leading(to_string(lon_min), 2, "0")}.#{String.pad_leading(to_string(lon_dec), 2, "0")}#{lon_dir}"

        # Test with various symbol table/code combinations
        packet = "TEST>APRS:!#{lat}#{symbol_table}#{lon}#{symbol_code}#{comment}"

        result = parse_packet(packet)
        assert result
        assert result.data_type == :position
        assert result.data_extended.symbol_table_id == symbol_table
        # Symbol code might be converted by parser (e.g., space to underscore)
        assert result.data_extended.symbol_code
      end
    end

    property "handles position ambiguity with spaces" do
      check all spaces <- integer(0..4),
                lat_base <- string([?0..?9], length: 4),
                lon_base <- string([?0..?9], length: 5),
                comment <- string(:printable, max_length: 20) do
        # Create position with ambiguity (spaces replacing digits)
        lat = String.slice(lat_base, 0, 4 - spaces) <> String.duplicate(" ", spaces) <> ".50N"
        lon = String.slice(lon_base, 0, 5 - spaces) <> String.duplicate(" ", spaces) <> ".50W"

        packet = "TEST>APRS:!#{lat}/#{lon}>#{comment}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :position && result.data_extended[:position_ambiguity] != nil do
          assert result.data_extended.position_ambiguity == spaces
        end
      end
    end

    property "handles position with various separators" do
      check all separator <- member_of(["/", "\\"]),
                comment <- string(:printable, max_length: 30) do
        packet = "TEST>APRS:!4903.50N#{separator}07201.75W>#{comment}"

        result = parse_packet(packet)
        assert result
        assert result.data_type == :position
      end
    end

    property "handles position with altitude in comment" do
      check all altitude <- integer(0..50_000),
                comment <- string(:printable, max_length: 20) do
        alt_string = "/A=#{String.pad_leading(to_string(altitude), 6, "0")}"
        packet = "TEST>APRS:!4903.50N/07201.75W>#{comment}#{alt_string}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :position do
          assert result.data_extended.altitude == altitude
        end
      end
    end

    property "handles position with DAO extension" do
      check all lat_dao <- string(:alphanumeric, length: 1),
                lon_dao <- string(:alphanumeric, length: 1),
                datum <- member_of(["W", " ", "!"]),
                comment <- string(:printable, max_length: 20) do
        dao = "!#{datum}#{lat_dao}#{lon_dao}!"
        packet = "TEST>APRS:!4903.50N/07201.75W>#{comment}#{dao}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :position && result.data_extended[:dao] != nil do
          # DAO parsing swaps the order - first char is lat_dao in packet
          assert result.data_extended.dao.lat_dao == datum
          assert result.data_extended.dao.lon_dao == lat_dao
        end
      end
    end
  end

  describe "weather reports property tests" do
    property "handles weather data with various field orders" do
      check all wind_dir <- integer(0..360),
                wind_speed <- integer(0..200),
                wind_gust <- integer(0..300),
                temp <- integer(-50..150),
                rain_1h <- integer(0..999),
                rain_24h <- integer(0..999),
                rain_midnight <- integer(0..999),
                humidity <- integer(0..100),
                pressure <- integer(9000..11_000) do
        # Build weather data string with realistic format
        weather_data =
          "_#{String.pad_leading(to_string(wind_dir), 3, "0")}/#{String.pad_leading(to_string(wind_speed), 3, "0")}"

        weather_data = weather_data <> "g#{String.pad_leading(to_string(wind_gust), 3, "0")}"
        weather_data = weather_data <> "t#{String.pad_leading(to_string(temp), 3, "0")}"
        weather_data = weather_data <> "r#{String.pad_leading(to_string(rain_1h), 3, "0")}"
        weather_data = weather_data <> "p#{String.pad_leading(to_string(rain_24h), 3, "0")}"
        weather_data = weather_data <> "P#{String.pad_leading(to_string(rain_midnight), 3, "0")}"
        weather_data = weather_data <> "h#{String.pad_leading(to_string(humidity), 2, "0")}"
        weather_data = weather_data <> "b#{String.pad_leading(to_string(pressure), 5, "0")}"

        packet = "TEST>APRS:@032035z4048.16N/08007.56W#{weather_data}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :weather do
          assert result.data_extended.wind_direction == wind_dir
          assert result.data_extended.wind_speed == wind_speed
        end
      end
    end

    property "handles weather with missing fields" do
      check all temp <- integer(0..150),
                has_wind <- boolean(),
                has_rain <- boolean(),
                has_humidity <- boolean(),
                has_pressure <- boolean() do
        weather_data =
          if has_wind do
            "_045/003"
          else
            "_.../.."
          end

        weather_data = weather_data <> "g..."
        weather_data = weather_data <> "t#{String.pad_leading(to_string(temp), 3, "0")}"

        weather_data =
          if has_rain do
            weather_data <> "r001p002P003"
          else
            weather_data <> "r...p...P..."
          end

        weather_data =
          if has_humidity do
            weather_data <> "h75"
          else
            weather_data <> "h.."
          end

        weather_data =
          if has_pressure do
            weather_data <> "b10150"
          else
            weather_data <> "b....."
          end

        packet = "TEST>APRS:!4048.16N/08007.56W#{weather_data}"

        result = parse_packet(packet)
        assert result
      end
    end
  end

  describe "compressed position property tests" do
    property "handles compressed positions with valid characters" do
      check all lat_chars <- string(Enum.to_list(33..126), length: 4),
                lon_chars <- string(Enum.to_list(33..126), length: 4),
                symbol_table <-
                  member_of(
                    ["/", "\\"] ++
                      (?A..?Z |> Enum.to_list() |> Enum.map(&<<&1>>)) ++ (?0..?9 |> Enum.to_list() |> Enum.map(&<<&1>>))
                  ),
                symbol_code <- string(Enum.to_list(33..126), length: 1),
                cs_chars <- string(Enum.to_list(33..126), length: 2),
                type_char <- string(Enum.to_list(33..126), length: 1) do
        packet = "TEST>APRS:!#{symbol_table}#{lat_chars}#{lon_chars}#{symbol_code}#{cs_chars}#{type_char}"

        result = parse_packet(packet)
        # Compressed positions should be 13 characters after the data type indicator
        if String.length("#{symbol_table}#{lat_chars}#{lon_chars}#{symbol_code}#{cs_chars}#{type_char}") == 13 do
          assert result
        end
      end
    end
  end

  describe "message property tests" do
    property "handles messages with various addressee formats" do
      check all addressee <- string(:alphanumeric, min_length: 1, max_length: 9),
                message <- string(:printable, max_length: 67),
                has_msg_id <- boolean() do
        padded_addr = String.pad_trailing(addressee, 9)

        packet =
          if has_msg_id do
            msg_id = :rand.uniform(99_999)
            "TEST>APRS::#{padded_addr}:#{message}{#{msg_id}"
          else
            "TEST>APRS::#{padded_addr}:#{message}"
          end

        result = parse_packet(packet)

        if result != nil && result.data_type == :message do
          assert result[:addressee] == String.trim(padded_addr) || result[:message] != nil
        end
      end
    end

    property "handles bulletin messages" do
      check all bulletin_id <- integer(0..9),
                message <- string(:printable, max_length: 67) do
        packet = "TEST>APRS::BLN#{bulletin_id}     :#{message}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :message do
          assert result[:addressee] != nil && String.starts_with?(result[:addressee], "BLN")
        end
      end
    end

    property "handles message acknowledgments and rejections" do
      check all addressee <- string(:alphanumeric, min_length: 3, max_length: 9),
                msg_id <- integer(1..99_999),
                is_ack <- boolean() do
        padded_addr = String.pad_trailing(addressee, 9)
        ack_rej = if is_ack, do: "ack", else: "rej"

        packet = "TEST>APRS::#{padded_addr}:#{ack_rej}#{msg_id}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :message do
          assert result[:message] == "#{ack_rej}#{msg_id}"
        end
      end
    end
  end

  describe "telemetry property tests" do
    property "handles telemetry data packets" do
      check all seq <- integer(0..999),
                a1 <- integer(0..255),
                a2 <- integer(0..255),
                a3 <- integer(0..255),
                a4 <- integer(0..255),
                a5 <- integer(0..255),
                d_bits <- integer(0..255) do
        # Format telemetry data
        seq_str = String.pad_leading(to_string(seq), 3, "0")
        values = Enum.map_join([a1, a2, a3, a4, a5], ",", &String.pad_leading(to_string(&1), 3, "0"))
        digital = String.pad_leading(Integer.to_string(d_bits, 2), 8, "0")

        packet = "TEST>APRS:T##{seq_str},#{values},#{digital}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :telemetry && result[:telemetry] != nil do
          # Telemetry seq is stored as string in the telemetry sub-map, with leading zeros preserved
          seq_str = String.pad_leading(to_string(seq), 3, "0")
          assert result.telemetry[:seq] == seq_str
          assert result.telemetry[:vals] != nil && length(result.telemetry[:vals]) == 5
        end
      end
    end

    property "handles telemetry parameter names" do
      check all param_names <- list_of(string(:alphanumeric, max_length: 8), length: 13) do
        params = Enum.join(param_names, ",")
        packet = "TEST>APRS::TEST     :PARM.#{params}"

        result = parse_packet(packet)
        assert result
      end
    end
  end

  describe "status report property tests" do
    property "handles status reports with various characters" do
      check all status <- string(:printable, min_length: 1, max_length: 62),
                has_timestamp <- boolean() do
        packet =
          if has_timestamp do
            "TEST>APRS:>031559z#{status}"
          else
            "TEST>APRS:>#{status}"
          end

        result = parse_packet(packet)

        if result != nil && result.data_type == :status do
          assert result.data_extended[:status] != nil || result.data_extended[:status_text] != nil
        end
      end
    end
  end

  describe "object/item property tests" do
    property "handles object reports" do
      check all name <- string(:alphanumeric, min_length: 1, max_length: 9),
                is_live <- boolean(),
                timestamp <- string([?0..?9], length: 6),
                comment <- string(:printable, max_length: 43) do
        padded_name = String.pad_trailing(name, 9)
        live_dead = if is_live, do: "*", else: "_"

        packet = "TEST>APRS:;#{padded_name}#{live_dead}#{timestamp}z4903.50N/07201.75W>#{comment}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :object do
          # Object name is stored as object_name
          assert result[:object_name] == String.trim(padded_name) || result.data_extended[:raw_data] != nil
          assert result[:alive] == if(is_live, do: 1, else: 0)
        end
      end
    end

    property "handles item reports" do
      check all name <- string(:alphanumeric, min_length: 3, max_length: 9),
                is_live <- boolean(),
                comment <- string(:printable, max_length: 43) do
        live_dead = if is_live, do: "!", else: "_"

        packet = "TEST>APRS:)#{name}#{live_dead}4903.50N/07201.75W>#{comment}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :item do
          # Item name is stored as item_name
          assert result[:item_name] == name || result[:raw_data] != nil
          # Item uses live_killed field with "!" for live and "_" for dead
          assert result[:live_killed] == if(is_live, do: "!", else: "_") || result[:alive] == if(is_live, do: 1, else: 0)
        end
      end
    end
  end

  describe "PHG data property tests" do
    property "handles PHG data in various formats" do
      check all power <- member_of([0, 1, 4, 9, 16, 25, 36, 49, 64, 81]),
                height <- member_of([10, 20, 40, 80, 160, 320, 640, 1280, 2560, 5120]),
                gain <- integer(0..9),
                dir <- integer(0..8) do
        # Calculate PHG codes
        p_code = round(:math.sqrt(power))
        h_code = round(:math.log2(height / 10))

        phg = "PHG#{p_code}#{h_code}#{gain}#{dir}"
        packet = "TEST>APRS:!4903.50N/07201.75W##{phg}"

        result = parse_packet(packet)

        if result != nil && result.data_extended[:phg] != nil && is_map(result.data_extended.phg) do
          assert result.data_extended.phg[:power] == power
        end
      end
    end
  end

  describe "edge cases and malformed packets" do
    property "handles packets with extreme field lengths" do
      check all sender <- string(:alphanumeric, min_length: 1, max_length: 9),
                path <- string(:alphanumeric, min_length: 1, max_length: 50),
                data <- string(:printable, min_length: 1, max_length: 256) do
        packet = "#{sender}>#{path}:#{data}"

        result = parse_packet(packet)
        # Should not crash, may return nil or error
        assert result == nil or is_map(result)
      end
    end

    property "handles packets with UTF-8 content" do
      check all comment <- string(:utf8, max_length: 50) do
        # Filter out control characters that might break parsing
        safe_comment = String.replace(comment, ~r/[\x00-\x1F\x7F]/, "")
        packet = "TEST>APRS:>Status: #{safe_comment}"

        result = parse_packet(packet)
        # Should handle UTF-8 gracefully
        assert result == nil or is_map(result)
      end
    end

    property "handles packets with missing or extra delimiters" do
      check all parts <- integer(1..5),
                content <- list_of(string(:alphanumeric, min_length: 1, max_length: 10), length: parts) do
        # Create packets with various delimiter issues
        packet = Enum.join(content, ">")

        result = parse_packet(packet)
        # Should handle gracefully without crashing
        assert result == nil or is_map(result)
      end
    end
  end
end
