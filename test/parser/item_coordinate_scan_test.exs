defmodule Aprs.ItemCoordinateScanTest do
  use ExUnit.Case, async: true

  alias Aprs.Item

  describe "loose coordinate scanning" do
    test "a well formed pair anywhere in the data is found" do
      item = Item.parse("junk 4903.50N/07201.75W more")

      assert_in_delta item.latitude, 49.058333, 0.000001
      assert_in_delta item.longitude, -72.029167, 0.000001
    end

    test "a latitude with too many degree digits is scanned but is not a coordinate" do
      item = Item.parse("12345.67N 07201.75W")

      assert item.latitude == nil
      assert item.longitude == nil
      assert item.raw_data == "12345.67N 07201.75W"
    end

    test "a longitude with too many degree digits is scanned but is not a coordinate" do
      item = Item.parse("4903.50N 123456.78E")

      assert item.latitude == nil
      assert item.longitude == nil
    end

    test "a latitude with no hemisphere byte is skipped and scanning continues" do
      item = Item.parse("4903.5X and 4903.50N/07201.75W")

      assert_in_delta item.latitude, 49.058333, 0.000001
      assert_in_delta item.longitude, -72.029167, 0.000001
    end

    test "a longitude with no hemisphere byte is not a longitude" do
      item = Item.parse("4903.50N 07201.7X")

      refute Map.has_key?(item, :latitude)
      assert item.raw_data == "4903.50N 07201.7X"
    end

    test "the longitude search stops at a line feed" do
      item = Item.parse("4903.50N no longitude\nx 5000.00N 07201.75W")

      assert item.latitude == 50.0
      assert_in_delta item.longitude, -72.029167, 0.000001
    end

    test "data with no coordinates at all is returned raw" do
      item = Item.parse("no coordinates here")

      assert item.raw_data == "no coordinates here"
      refute Map.has_key?(item, :latitude)
    end
  end
end
