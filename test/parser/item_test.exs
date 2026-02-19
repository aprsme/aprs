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
    end

    test "parses an item with no position data" do
      result = Item.parse(")Item!No Position Data")

      assert result.data_type == :item
      assert result.item_name == "Item"
      assert result.live_killed == "!"
      assert result.position_format == :unknown
      assert result.comment == "No Position Data"
    end

    test "handles item with no regex match on item_name_and_data" do
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
  end
end
