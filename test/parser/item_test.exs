defmodule Aprs.ItemTest do
  use ExUnit.Case, async: true

  alias Aprs.Item

  describe "parse/1" do
    test "parses an item with uncompressed position" do
      result = Item.parse(")GATE!4903.50N/07201.75W>Test item")

      assert result.data_type == :item
      assert result.item_name == "GATE"
      assert result.live_killed == "!"
      assert_in_delta result.latitude, 49.0583, 0.0001
      assert_in_delta result.longitude, -72.0292, 0.0001
      assert result.position_format == :uncompressed
      assert result.symbol_code == ">"
      assert result.symbol_table_id == "/"
      assert result.comment == "Test item"
      assert result.alive == 1
      assert result.itemname == "GATE"
      assert result.has_position
      assert result.posresolution == 18.52
    end

    test "parses an item with compressed position" do
      result = Item.parse(")An_Item_ _/5L`a=;s#_comment")

      assert result.data_type == :item
      assert result.item_name == "An_Item_"
      assert result.live_killed == "_"
      assert result.position_format == :compressed
      assert result.symbol_table_id == "/"
      assert result.symbol_code == "_"
      assert result.compression_type == "m"
      assert result.comment == "ment"
      assert is_float(result.latitude)
      assert is_float(result.longitude)
      assert result.alive == 0
      assert result.itemname == "An_Item_"
      assert result.has_position
      assert result.posresolution == 0.291
    end

    test "decodes compressed GGA cs bytes as altitude" do
      result = Item.parse(")GATE!/abcdabcd>!!1Test")

      assert result.position_format == :compressed
      assert result.altitude == 1.0
      refute Map.has_key?(result, :course)
      refute Map.has_key?(result, :speed)
    end

    test "parses an item with no position data" do
      result = Item.parse(")Item!No Position Data")

      assert result.data_type == :item
      assert result.item_name == "Item"
      assert result.live_killed == "!"
      assert result.position_format == :unknown
      assert result.comment == "No Position Data"
    end

    test "marks a killed item as not alive" do
      result = Item.parse(")AID #2_4903.50N/07201.75WA")

      assert result.item_name == "AID #2"
      assert result.itemname == "AID #2"
      assert result.live_killed == "_"
      assert result.alive == 0
    end

    test "preserves raw item data without a live or killed indicator" do
      result = Item.parse(")This does not match the regex")

      assert result == %{
               data_type: :item,
               item_name: "This does not match the regex",
               raw_data: ")This does not match the regex"
             }
    end

    test "parses raw data with position information" do
      result = Item.parse(" raw data 4903.50N/07201.75W with position")
      assert result.data_type == :item
      assert result.raw_data == " raw data 4903.50N/07201.75W with position"
      # This path uses Aprs.Position.parse_aprs_position which returns floats
      assert result.latitude
      assert result.longitude
    end

    test "handles raw data without position information" do
      result = Item.parse("some other random data")
      assert result == %{raw_data: "some other random data", data_type: :item}
    end

    test "parses an item starting with %" do
      result = Item.parse("%GATE!4903.50N/07201.75W>Test item")
      assert result.data_type == :item
      assert result.item_name == "GATE"
    end

    test "extracts PHG data from item comment" do
      result = Item.parse(")GATE!4903.50N/07201.75W>PHG5132 description")
      assert result.phg == "5132"
      assert result.comment == "description"
    end

    test "parses course, speed, and altitude from an item comment" do
      result = Item.parse(")AID #2!4903.50N/07201.75WA088/036/A=001234Test")

      assert result.course == 88
      assert result.speed == 36.0
      assert result.altitude == 1234.0
      assert result.comment == "Test"
    end

    test "captures RNG and DAO precision from an item comment" do
      result = Item.parse(")GATE!4903.50N/07201.75W>RNG0050!W12!Test")

      assert result.radiorange == 50
      assert result.daodatumbyte == "W"
      assert result.latitude > 49.0583
      assert result.longitude < -72.02917
      assert result.comment == "Test"
    end

    test "parses weather from an item using the weather symbol" do
      result = Item.parse(")WX!4903.50N/07201.75W_220/005g010t050Tail")

      assert result.weather.wind_direction == 220
      assert result.weather.wind_speed == 5
      assert result.weather.temperature == 50
      assert result.comment == "Tail"
    end

    test "uncompressed position parsing falls back to :unknown when too short" do
      # Item name "X" (1-9 chars), status "!", followed by short non-digit/non-compressed prefix
      # This will fail both compressed (needs 13 bytes) and uncompressed (needs 19 bytes)
      result = Item.parse(")X!short")
      assert result.position_format == :unknown
    end

    test "uncompressed-prefix digit but data too short hits parse_uncompressed_position fallback" do
      # First byte after ! is a digit, so parse_item_position dispatches to
      # parse_uncompressed_position; the binary is shorter than the 19-byte
      # pattern, so the fallback clause returns position_format: :unknown.
      result = Item.parse(")X!1abc")
      assert result.position_format == :unknown
      assert result.comment == "1abc"
    end

    test "compressed position with invalid longitude returns nil longitude" do
      # 13 bytes starting with /, with valid lat (4 chars) but invalid lon (non-base91)
      # `/` + 4 lat-chars + 4 lon-chars + symbol + cs(2) + compression_type(1) = 13 bytes
      # Use control chars (below 33) for longitude to fail base91 validation
      bad_lon = <<0, 0, 0, 0>>
      data = ")X!" <> "/" <> "5L`8" <> bad_lon <> ">" <> "  " <> "T"
      result = Item.parse(data)
      # When longitude conversion fails, latitude or longitude is nil → falls into unknown branch
      assert result.position_format == :unknown
    end

    test "compressed position parsing fallback when too short" do
      # First char is `/` (compressed indicator) but length < 13 bytes
      # Item.parse_item_position takes a full uncompressed (19+ bytes) check, but compressed branch needs >=13
      # Use a 13-byte string starting with `/` then symbols to force decompression failure
      result = Item.parse(")X!/abcdefghijkl")
      assert is_map(result)
      assert result.data_type == :item
    end
  end
end
