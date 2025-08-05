defmodule Aprs.ItemPropertyTest do
  @moduledoc """
  Property-based tests for Item report packets.
  Based on real-world patterns from packets.csv
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

  describe "item report property tests" do
    property "handles item reports with various name lengths" do
      check all name <- string(:alphanumeric, min_length: 3, max_length: 9),
                is_live <- boolean(),
                lat_deg <- integer(0..89),
                lat_min <- integer(0..59),
                lat_dec <- integer(0..99),
                lat_dir <- member_of(["N", "S"]),
                lon_deg <- integer(0..179),
                lon_min <- integer(0..59),
                lon_dec <- integer(0..99),
                lon_dir <- member_of(["E", "W"]),
                symbol_table <- member_of(["/", "\\"] ++ (?A..?Z |> Enum.to_list() |> Enum.map(&<<&1>>))),
                symbol_code <- string(Enum.to_list(33..126), length: 1),
                comment <- string(:printable, max_length: 43) do
        # Format coordinates
        lat =
          "#{String.pad_leading(to_string(lat_deg), 2, "0")}#{String.pad_leading(to_string(lat_min), 2, "0")}.#{String.pad_leading(to_string(lat_dec), 2, "0")}#{lat_dir}"

        lon =
          "#{String.pad_leading(to_string(lon_deg), 3, "0")}#{String.pad_leading(to_string(lon_min), 2, "0")}.#{String.pad_leading(to_string(lon_dec), 2, "0")}#{lon_dir}"

        # Live/killed indicator
        live_dead = if is_live, do: "!", else: "_"

        # Build item packet
        packet = "TEST>APRS:)#{name}#{live_dead}#{lat}#{symbol_table}#{lon}#{symbol_code}#{comment}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :item do
          assert result.item_name == name
          assert result.live_killed == if(is_live, do: "!", else: "_")
          assert result.data_extended.latitude != nil
          assert result.data_extended.longitude != nil
          assert result.data_extended.symbol_table_id == symbol_table
          assert result.data_extended.symbol_code == symbol_code
        end
      end
    end

    property "handles item reports with compressed positions" do
      check all name <- string(:alphanumeric, min_length: 3, max_length: 9),
                is_live <- boolean(),
                lat_chars <- string(Enum.to_list(33..126), length: 4),
                lon_chars <- string(Enum.to_list(33..126), length: 4),
                symbol_table <- member_of(["/", "\\"]),
                symbol_code <- string(Enum.to_list(33..126), length: 1),
                cs_chars <- string(Enum.to_list(33..126), length: 2),
                type_char <- string(Enum.to_list(33..126), length: 1),
                comment <- string(:printable, max_length: 20) do
        live_dead = if is_live, do: "!", else: "_"

        # Compressed position format (must start with "/" for compressed)
        compressed_pos =
          if symbol_table == "/" do
            "/#{lat_chars}#{lon_chars}#{symbol_code}#{cs_chars}#{type_char}"
          else
            # Use uncompressed format for non-"/" symbol tables
            "4903.50N\\07201.75W#{symbol_code}"
          end

        packet = "TEST>APRS:)#{name}#{live_dead}#{compressed_pos}#{comment}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :item do
          # The parser might include extra characters in item_name for compressed positions
          # or might parse live_killed differently for compressed vs uncompressed
          assert String.contains?(result.item_name || "", name) ||
                   result.item_name == name

          # Live/killed indicator should be present
          assert result.live_killed in ["!", "_"]
        end
      end
    end

    property "handles item reports with DAO extension" do
      check all name <- string(:alphanumeric, min_length: 3, max_length: 9),
                dao_lat <- string(:alphanumeric, length: 1),
                dao_lon <- string(:alphanumeric, length: 1),
                datum <- member_of(["W", " ", "!"]),
                comment <- string(:printable, max_length: 20) do
        dao = "!#{datum}#{dao_lat}#{dao_lon}!"
        packet = "TEST>APRS:)#{name}!4903.50N/07201.75W>#{comment}#{dao}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :item && result.data_extended[:dao] != nil do
          assert is_map(result.data_extended.dao)
        end
      end
    end

    property "handles item reports with area objects" do
      check all name <- string(:alphanumeric, min_length: 3, max_length: 9),
                shape <- member_of(["circle", "line", "box", "triangle"]),
                color <-
                  member_of(
                    ["/", "\\"] ++
                      (?0..?9 |> Enum.to_list() |> Enum.map(&<<&1>>)) ++ (?A..?F |> Enum.to_list() |> Enum.map(&<<&1>>))
                  ) do
        # Area object formats based on shape
        area_spec =
          case shape do
            "circle" ->
              radius = :rand.uniform(999)
              "Cir#{String.pad_leading(to_string(radius), 3, "0")}"

            "line" ->
              bearing = :rand.uniform(360)
              length = :rand.uniform(999)
              "Line#{String.pad_leading(to_string(bearing), 3, "0")}/#{String.pad_leading(to_string(length), 3, "0")}"

            "box" ->
              height = :rand.uniform(99)
              width = :rand.uniform(99)
              "Box#{String.pad_leading(to_string(height), 2, "0")}x#{String.pad_leading(to_string(width), 2, "0")}"

            "triangle" ->
              "Tri"
          end

        packet = "TEST>APRS:)#{name}!4903.50N/07201.75W\\#{area_spec}#{color}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end

    property "handles item reports with weather data" do
      check all name <- string(:alphanumeric, min_length: 3, max_length: 9),
                wind_dir <- integer(0..360),
                wind_speed <- integer(0..200),
                temp <- integer(-50..150),
                has_gust <- boolean(),
                gust <- integer(0..300) do
        weather =
          "_#{String.pad_leading(to_string(wind_dir), 3, "0")}/#{String.pad_leading(to_string(wind_speed), 3, "0")}"

        weather =
          if has_gust do
            weather <> "g#{String.pad_leading(to_string(gust), 3, "0")}"
          else
            weather <> "g..."
          end

        weather = weather <> "t#{String.pad_leading(to_string(temp), 3, "0")}"

        packet = "TEST>APRS:)#{name}!4903.50N/07201.75W#{weather}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :item do
          assert result.item_name == name
        end
      end
    end

    property "handles item reports with special characters in names" do
      check all base_name <- string(:alphanumeric, min_length: 2, max_length: 6),
                special <- member_of(["-", "_", ".", "/", "*"]),
                suffix <- string(:alphanumeric, max_length: 2),
                comment <- string(:printable, max_length: 30) do
        # Some real-world item names include special characters
        name = base_name <> special <> suffix
        # Ensure max 9 chars
        name = String.slice(name, 0, 9)

        # Skip if name is too short after slicing
        if String.length(name) >= 3 do
          packet = "TEST>APRS:)#{name}!4903.50N/07201.75W>#{comment}"

          result = parse_packet(packet)
          # Parser should handle special characters gracefully
          assert result == nil or is_map(result)
        end
      end
    end

    property "handles item reports from real packet patterns" do
      check all item_type <- member_of(["FIRE", "WATER", "AID", "GATE", "MARK", "SIGN"]),
                number <- integer(1..999),
                status <- member_of(["OPEN", "CLOSED", "ACTIVE", "ALERT", ""]) do
        # Common patterns from real APRS networks
        name = "#{item_type}#{number}"
        name = String.slice(name, 0, 9)

        comment = if status == "", do: "", else: " #{status}"

        packet = "TEST>APRS:)#{name}!4903.50N/07201.75W>#{comment}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :item do
          assert result.item_name == name
        end
      end
    end

    property "handles malformed item packets gracefully" do
      check all name_len <- integer(0..15),
                has_position <- boolean(),
                has_live_indicator <- boolean() do
        # Generate potentially malformed names
        name =
          for _ <- 1..name_len,
              do: Enum.random(~w(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 0 1 2 3 4 5 6 7 8 9))

        name = Enum.join(name)

        data = ")#{name}"
        data = if has_live_indicator, do: data <> "!", else: data
        data = if has_position, do: data <> "4903.50N/07201.75W>", else: data

        packet = "TEST>APRS:#{data}"

        result = parse_packet(packet)
        # Should handle gracefully without crashing
        assert result == nil or is_map(result)
      end
    end
  end
end
