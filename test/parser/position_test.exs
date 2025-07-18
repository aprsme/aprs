defmodule Aprs.PositionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Position
  alias Aprs.Types.Position, as: PositionStruct

  describe "parse/1" do
    test "returns a Position struct for valid input" do
      input = "4903.50N/12311.12W>comment"
      result = Position.parse(input)
      assert %PositionStruct{} = result
    end

    test "returns nil or struct with nil lat/lon for invalid input" do
      for input <- ["", "invalidstring", "12345678N/123456789W"] do
        result = Position.parse(input)
        assert result == nil or match?(%PositionStruct{latitude: nil, longitude: nil}, result)
      end
    end

    test "parses position with DAO extension in comment" do
      result = Position.parse("4903.50N/07201.75W>Test!ABZ! position")
      assert %PositionStruct{} = result
      assert result.dao == %{lat_dao: "A", lon_dao: "B", datum: "WGS84"}
    end

    test "parses ambiguous position (spaces in lat/lon)" do
      result = Position.parse("49 3.50N/07201.7 W>Ambiguous")
      assert %PositionStruct{} = result
      assert result.position_ambiguity == 1
    end

    test "returns struct with nil lat/lon for structurally valid but invalid lat/lon" do
      # Valid length but not matching regex
      result = Position.parse("abcdefgh/ijklmnopq>Invalid")
      assert %PositionStruct{latitude: nil, longitude: nil} = result
    end
  end

  property "returns nil or struct with nil lat/lon for random invalid strings" do
    check all s <- StreamData.string(:ascii, min_length: 1, max_length: 30),
              not String.match?(s, ~r/^\d{4}\.\d{2}[NS][\/\\]\d{5}\.\d{2}[EW].+/) do
      result = Position.parse(s)
      assert result == nil or match?(%PositionStruct{latitude: nil, longitude: nil}, result)
    end
  end

  describe "parse_aprs_position/2" do
    test "parses valid APRS lat/lon strings" do
      result = Position.parse_aprs_position("4903.50N", "07201.75W")

      if result.latitude == nil or result.longitude == nil do
        flunk("parse_aprs_position/2 returned nil for latitude or longitude")
      end

      assert Decimal.equal?(Decimal.round(result.latitude, 6), Decimal.new("49.058333"))
      assert Decimal.equal?(Decimal.round(result.longitude, 6), Decimal.new("-72.029167"))
    end

    test "returns nils for invalid strings" do
      assert %{latitude: nil, longitude: nil} = Position.parse_aprs_position("bad", "data")
    end

    test "parses southern and eastern hemispheres" do
      result = Position.parse_aprs_position("1234.56S", "04540.70E")
      assert Decimal.compare(result.latitude, Decimal.new(0)) == :lt
      assert Decimal.compare(result.longitude, Decimal.new(0)) == :gt
    end

    test "returns nil for malformed but structurally valid input" do
      result = Position.parse_aprs_position("12345678", "123456789")
      assert %{latitude: nil, longitude: nil} = result
    end
  end

  describe "calculate_position_ambiguity/2" do
    test "returns correct ambiguity for no spaces" do
      assert Position.calculate_position_ambiguity("4903.50N", "07201.75W") == 0
    end

    test "returns correct ambiguity for one space in each string" do
      assert Position.calculate_position_ambiguity("49 3.50N", "07201.7 W") == 1
    end

    test "returns correct ambiguity for two spaces in each string" do
      assert Position.calculate_position_ambiguity("4  3.50N", "0720  .7W") == 2
    end
  end

  describe "count_spaces/1" do
    property "counts spaces correctly" do
      check all s <- StreamData.string(:ascii, min_length: 0, max_length: 20) do
        assert Position.count_spaces(s) == s |> String.graphemes() |> Enum.count(&(&1 == " "))
      end
    end
  end

  describe "parse_dao_extension/1" do
    test "parses valid DAO extension" do
      assert %{lat_dao: "A", lon_dao: "B", datum: "WGS84"} = Position.parse_dao_extension("!ABZ!")
    end

    test "returns nil for no DAO extension" do
      assert Position.parse_dao_extension("no dao here") == nil
    end
  end

  describe "specific failing packet" do
    test "VE6LY-7 packet with mic_e data type" do
      packet = "VE6LY-7>T5TYR2,F5ZFL-4*,WIDE1,WIDE2-1,qAR,HB9GYR-10:`|apl [/>\":E}432.812MHzAndy S andy@nsnw.ca^"

      # Test the full packet parsing
      result = Aprs.parse(packet)
      assert {:ok, parsed} = result

      # Check if we have extended data
      if parsed[:data_extended] do
        data = parsed[:data_extended]
        # The packet should have location data but it's not being decoded properly
        # This test will help us understand what's happening
        assert data[:data_type] == :mic_e
        # VE6LY-7 is in southern France, so longitude should be positive (east)
        # and in the correct range for France (roughly 0-10 degrees east)
        if data[:longitude] do
          lon = Decimal.to_float(data[:longitude])
          # The longitude should be positive for eastern hemisphere (France)
          assert lon > 0, "Longitude should be positive for eastern hemisphere (France), got #{lon}"
          # Should be in reasonable range for France (roughly 0-10 degrees east)
          assert lon < 10, "Longitude should be in reasonable range for France, got #{lon}"
        end
      end
    end
  end

  describe "from_aprs/2" do
    test "delegates to parse_aprs_position" do
      result = Position.from_aprs("4903.50N", "07201.75W")
      refute is_nil(result.latitude)
      refute is_nil(result.longitude)
      assert Decimal.equal?(Decimal.round(result.latitude, 6), Decimal.new("49.058333"))
      assert Decimal.equal?(Decimal.round(result.longitude, 6), Decimal.new("-72.029167"))
    end
  end

  describe "from_decimal/2" do
    test "creates position from decimal values" do
      result = Position.from_decimal("45.5", "-73.6")
      assert Decimal.equal?(result.latitude, Decimal.new("45.5"))
      assert Decimal.equal?(result.longitude, Decimal.new("-73.6"))
    end

    test "handles integer input" do
      result = Position.from_decimal(45, -73)
      assert Decimal.equal?(result.latitude, Decimal.new(45))
      assert Decimal.equal?(result.longitude, Decimal.new(-73))
    end
  end

  describe "calculate_position_ambiguity/2 edge cases" do
    test "returns 0 for mismatched space counts" do
      # Test the default case in @ambiguity_levels map
      assert Position.calculate_position_ambiguity("49 3.50N", "07201.75W") == 0
      assert Position.calculate_position_ambiguity("4903.50N", "07201.7 W") == 0
    end

    test "returns correct ambiguity for 3 spaces" do
      assert Position.calculate_position_ambiguity("4   .50N", "072   .7W") == 3
    end

    test "returns correct ambiguity for 4 spaces" do
      assert Position.calculate_position_ambiguity("    .50N", "072    .W") == 4
    end
  end
end
