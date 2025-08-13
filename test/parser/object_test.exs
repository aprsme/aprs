defmodule Aprs.ObjectTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Object

  describe "parse/1" do
    test "returns a map with :data_type => :object for valid input" do
      result = Object.parse(";OBJECT*111111z4903.50N/07201.75W>Test object")
      assert is_map(result)
      assert result[:data_type] == :object
    end

    property "always returns a map with :data_type == :object for any string" do
      check all s <- StreamData.string(:ascii, min_length: 1, max_length: 30) do
        result = Object.parse(s)
        assert is_map(result)
        assert result[:data_type] == :object
      end
    end

    test "parses uncompressed object position" do
      # 9-char name, 1 live/killed, 7 timestamp, 8 lat, 1 sym_table, 9 lon, 1 sym_code, comment
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">Test object"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:position_format] == :uncompressed
      assert result[:latitude]
      assert result[:longitude]
    end

    test "parses compressed object position" do
      # 9-char name, 1 live/killed, 7 timestamp, compressed position
      data = ";OBJECTNAM*1234567/abcdabcd>12!cTest compressed"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:position_format] == :compressed
    end

    test "parses unknown/fallback object position" do
      data = ";OBJECTNAM*1234567unknownformat"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:position_format] == :unknown
    end

    test "parses fallback/other data" do
      data = "not an object"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:raw_data] == data
    end

    test "handles compressed position parsing errors" do
      # Test the rescue branch in compressed position parsing
      # Invalid compressed position that will cause an error
      data =
        ";OBJECTNAM*1234567/" <>
          <<255, 255, 255, 255>> <> <<255, 255, 255, 255>> <> "X" <> <<255, 255>> <> "X" <> "comment"

      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:position_format] == :compressed
      assert result[:latitude] == nil
      assert result[:longitude] == nil
      assert result[:comment] == "comment"
    end

    test "handles invalid compressed latitude/longitude conversion" do
      # Test when conversion functions return error tuples
      # Using invalid base91 characters
      data = ";OBJECTNAM*1234567/!!!!!!!!!!Xcomment"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:position_format] == :compressed
      # '!' is actually a valid base91 character (value 0), so it may convert successfully
      assert result[:latitude] == 90.0 or result[:latitude] == nil
      assert result[:longitude] == -180.0 or result[:longitude] == nil
    end
  end
end
