defmodule Aprs.MicEPropertyTest do
  @moduledoc """
  Property-based tests for Mic-E format packets.
  Mic-E is a compressed format that encodes position, speed, and course in the destination field.
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

  describe "Mic-E destination field encoding" do
    property "handles various Mic-E destination patterns" do
      check all _lat_deg <- integer(0..89),
                _lat_min <- integer(0..59),
                _lat_hun <- integer(0..99),
                _is_north <- boolean(),
                _lon_offset <- integer(0..2),
                _is_west <- boolean(),
                _msg_code <- integer(0..7) do
        # Mic-E encodes latitude in destination field
        # Each character encodes part of the latitude and message bits

        # This is a simplified test - actual Mic-E encoding is complex
        # Just verify parser doesn't crash on various destination patterns
        for_result =
          for _ <- 1..6 do
            Enum.random([
              "0",
              "1",
              "2",
              "3",
              "4",
              "5",
              "6",
              "7",
              "8",
              "9",
              "A",
              "B",
              "C",
              "D",
              "E",
              "F",
              "G",
              "H",
              "I",
              "J",
              "K",
              "L",
              "P",
              "Q",
              "R",
              "S",
              "T",
              "U",
              "V",
              "W",
              "X",
              "Y",
              "Z"
            ])
          end

        dest_chars = Enum.join(for_result)

        # Mic-E data field contains compressed lon/speed/course
        info_field = "`" <> :binary.list_to_bin(Enum.map(1..8, fn _ -> :rand.uniform(127 - 28) + 28 end))

        packet = "TEST>#{dest_chars},WIDE1-1:#{info_field}"

        result = parse_packet(packet)
        # Should handle without crashing
        assert result == nil or is_map(result)
      end
    end

    property "handles Mic-E with telemetry data" do
      check all telemetry_flag <- member_of(["`", "'"]),
                has_telemetry <- boolean() do
        # Example valid Mic-E destination
        dest = "T7RSUV"

        # Basic Mic-E position data
        base_data =
          :binary.list_to_bin([
            # Longitude degrees
            :rand.uniform(127 - 28) + 28,
            # Longitude minutes
            :rand.uniform(127 - 28) + 28,
            # Longitude hundredths
            :rand.uniform(127 - 28) + 28,
            # Speed/course
            :rand.uniform(127 - 28) + 28,
            # Speed
            :rand.uniform(127 - 28) + 28,
            # Course
            :rand.uniform(127 - 28) + 28
          ])

        info =
          if has_telemetry do
            # Add telemetry values after position data
            telemetry =
              :binary.list_to_bin([
                :rand.uniform(127 - 28) + 28,
                :rand.uniform(127 - 28) + 28
              ])

            telemetry_flag <> base_data <> telemetry
          else
            telemetry_flag <> base_data
          end

        packet = "TEST>#{dest},WIDE1-1:#{info}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles Mic-E status text variations" do
      check all status_text <- string(:printable, max_length: 20),
                symbol_table <-
                  member_of(
                    ["/", "\\"] ++
                      (?A..?Z |> Enum.to_list() |> Enum.map(&<<&1>>)) ++ (?0..?9 |> Enum.to_list() |> Enum.map(&<<&1>>))
                  ),
                symbol_code <- string(:ascii, length: 1) do
        # Example Mic-E destination
        dest = "T7STUV"

        # Mic-E with status text
        base_data = :binary.list_to_bin(Enum.map(1..8, fn _ -> :rand.uniform(127 - 28) + 28 end))
        info = "`" <> base_data <> symbol_table <> symbol_code <> status_text

        packet = "TEST>#{dest},WIDE1-1:#{info}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :mic_e do
          # Check symbol was parsed
          assert result.data_extended[:symbol_table_id] != nil
          assert result.data_extended[:symbol_code] != nil
        end
      end
    end

    property "handles Mic-E altitude encoding" do
      check all altitude <- integer(-10_000..100_000),
                has_altitude <- boolean() do
        dest = "T7RSUV"
        base_data = :binary.list_to_bin(Enum.map(1..8, fn _ -> :rand.uniform(127 - 28) + 28 end))

        info =
          if has_altitude do
            # Altitude in Mic-E is encoded in specific format
            # Simplified for testing
            alt_text = " /A=#{String.pad_leading(to_string(altitude), 6, "0")}"
            "`" <> base_data <> alt_text
          else
            "`" <> base_data
          end

        packet = "TEST>#{dest},WIDE1-1:#{info}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "Mic-E message type encoding" do
    property "handles different Mic-E message types" do
      check all msg_type <- member_of([:emergency, :priority, :custom, :standard]) do
        # Different destination patterns encode different message types
        dest =
          case msg_type do
            # Pattern for emergency
            :emergency -> "TTRTTV"
            # Pattern for priority  
            :priority -> "TSRTTV"
            # Pattern for custom
            :custom -> "T7STUV"
            # Standard
            _ -> "T7RSUV"
          end

        info = "`" <> :binary.list_to_bin(Enum.map(1..8, fn _ -> :rand.uniform(127 - 28) + 28 end))
        packet = "TEST>#{dest},WIDE1-1:#{info}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :mic_e && result.data_extended[:mic_e_msg] != nil do
          # Verify message type was decoded
          assert is_binary(result.data_extended.mic_e_msg)
        end
      end
    end
  end

  describe "timestamped position property tests" do
    property "handles various timestamp formats" do
      check all day <- integer(1..31),
                hour <- integer(0..23),
                minute <- integer(0..59),
                tz <- member_of(["z", "h", "/"]),
                comment <- string(:printable, max_length: 30) do
        # Format timestamp
        timestamp =
          "#{String.pad_leading(to_string(day), 2, "0")}" <>
            "#{String.pad_leading(to_string(hour), 2, "0")}" <>
            "#{String.pad_leading(to_string(minute), 2, "0")}" <>
            tz

        packet = "TEST>APRS:@#{timestamp}4903.50N/07201.75W>#{comment}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :timestamped_position do
          assert result.data_extended.timestamp != nil
        end
      end
    end

    property "handles timestamped positions with weather data" do
      check all timestamp <- string([?0..?9], length: 6),
                wind_dir <- integer(0..360),
                wind_speed <- integer(0..200),
                temp <- integer(-50..150) do
        weather =
          "_#{String.pad_leading(to_string(wind_dir), 3, "0")}/" <>
            "#{String.pad_leading(to_string(wind_speed), 3, "0")}" <>
            "g...t#{String.pad_leading(to_string(temp), 3, "0")}"

        packet = "TEST>APRS:@#{timestamp}z4903.50N/07201.75W#{weather}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :weather do
          assert result.data_extended.wind_direction == wind_dir
          assert result.data_extended.wind_speed == wind_speed
        end
      end
    end

    property "handles timestamped compressed positions" do
      check all timestamp <- string([?0..?9], length: 6),
                lat_chars <- string(Enum.to_list(33..126), length: 4),
                lon_chars <- string(Enum.to_list(33..126), length: 4),
                symbol_table <- member_of(["/", "\\"]),
                symbol_code <- string(Enum.to_list(33..126), length: 1) do
        packet = "TEST>APRS:@#{timestamp}z#{symbol_table}#{lat_chars}#{lon_chars}#{symbol_code}   "

        result = parse_packet(packet)
        # Should handle timestamped compressed positions
        assert result == nil or is_map(result)
      end
    end
  end

  describe "Mic-E edge cases from real packets" do
    property "handles Mic-E packets with non-standard characters" do
      check all dest_suffix <- string(:alphanumeric, min_length: 0, max_length: 3) do
        # Real example patterns from packets.csv
        destinations = ["TSPU88", "SUUVU2", "TP0V4X", "APLC13", "S7U0U6"]
        dest = Enum.random(destinations)

        # Mic-E info field with various byte values
        info_bytes =
          for _ <- 1..10 do
            # Mic-E can have bytes from 0x1C to 0x7F
            :rand.uniform(127 - 28) + 28
          end

        info = "`" <> :binary.list_to_bin(info_bytes)
        packet = "TEST>#{dest}#{dest_suffix},WIDE1-1:#{info}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles Mic-E with manufacturer-specific data" do
      check all mfr <- member_of([" ", "!", "#", "$", "%", "&", "'", "(", ")"]),
                data_len <- integer(0..20) do
        dest = "T7RSUV"
        base_data = :binary.list_to_bin(Enum.map(1..8, fn _ -> :rand.uniform(127 - 28) + 28 end))

        # Add manufacturer specific data
        mfr_data = :binary.list_to_bin(Enum.map(1..data_len, fn _ -> :rand.uniform(95) + 32 end))
        info = "`" <> base_data <> mfr <> mfr_data

        packet = "TEST>#{dest},WIDE1-1:#{info}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end
end
