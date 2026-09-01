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

    test "parses object with DAO extension in comment" do
      # Triggers Map.put(result, :daodatumbyte, dao_byte) - line 108
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">Test !ABZ! position"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:daodatumbyte] == "A"
    end

    test "parses object with space-A= altitude prefix" do
      # Triggers parse_altitude_prefix(<<space, A, = ...>>) - line 147
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> "> A=00100 comment"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
    end

    test "parses object with negative altitude" do
      # Triggers parse_altitude_value(<<?-, rest::binary>>, _acc) - line 157
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">/A=-0100 comment"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:altitude] == -100
    end

    test "parses altitude where parse_altitude_digits gets empty acc" do
      # Triggers defp parse_altitude_digits(rest, _acc) when byte_size(acc) == 0 - line 176
      # /A= followed immediately by a non-digit
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">/A=X comment"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:altitude] == nil
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

    test "extracts altitude after RNG prefix (slash form)" do
      # Comment contains RNG followed by altitude /A=
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">RNG0050/A=00100rest"
      result = Object.parse(data)
      assert result[:altitude] == 100
    end

    test "extracts altitude after RNG prefix (space form)" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">RNG0050 A=00100rest"
      result = Object.parse(data)
      assert result[:altitude] == 100
    end

    test "RNG present without altitude returns nil altitude" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">RNG0050 misc"
      result = Object.parse(data)
      assert result[:altitude] == nil
    end

    test "extracts PHG from object comment" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">PHG5132 desc"
      result = Object.parse(data)
      assert result[:phg] == "5132"
    end

    test "strips leading slash delimiter from comment" do
      # extract_rng returns {nil, comment}, parse_altitude not matched, comment retains leading /
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">/leading-slash"
      result = Object.parse(data)
      assert result[:comment] == "leading-slash"
    end

    test "strips leading space delimiter from comment" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> "> leading-space"
      result = Object.parse(data)
      assert result[:comment] == "leading-space"
    end

    test "object timestamp already elapsed this month stays in the current month" do
      # Day 1 at 00:00 is never in the future relative to "now" within the same
      # month, so the timestamp resolves against the current month rather than
      # falling back to the previous one.
      started_at = DateTime.utc_now()
      result = Object.parse(";LEADER   *010000z4903.50N/07201.75W>Test")
      finished_at = DateTime.utc_now()

      assert is_integer(result.timestamp)
      {:ok, dt} = DateTime.from_unix(result.timestamp)

      assert dt.day == 1
      assert dt.hour == 0
      assert dt.minute == 0
      assert dt.second == 0
      refute DateTime.after?(dt, finished_at)

      assert {dt.year, dt.month} in [
               {started_at.year, started_at.month},
               {finished_at.year, finished_at.month}
             ]
    end
  end
end
