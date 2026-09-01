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

      assert result[:has_position]
      assert result[:posresolution] == 18.52
    end

    test "parses compressed object position" do
      # 9-char name, 1 live/killed, 7 timestamp, compressed position
      data = ";OBJECTNAM*1234567/abcdabcd>12!cTest compressed"
      result = Object.parse(data)
      assert is_map(result)
      assert result[:data_type] == :object
      assert result[:position_format] == :compressed
    end

    test "parses a compressed object with an alternate symbol table" do
      result = Object.parse(";LEADER   *092345z\\5L!!<*e7>7P[Test")

      assert result.position_format == :compressed
      assert result.format == :compressed
      assert result.symbol_table_id == "\\"
      assert result.has_position
      assert result.posresolution == 0.291
      assert is_float(result.latitude)
      assert is_float(result.longitude)
      assert result.comment == "Test"
    end

    test "decodes compressed GGA cs bytes as altitude" do
      result = Object.parse(";LEADER   *092345z/abcdabcd>!!1Test")

      assert result.altitude == 1.0
      refute Map.has_key?(result, :course)
      refute Map.has_key?(result, :speed)
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

    test "parses and applies a DAO extension in the comment" do
      result = Object.parse(";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">Test !W12! position")

      assert result.data_type == :object
      assert result.daodatumbyte == "W"
      refute String.contains?(result.comment, "!W12!")
      assert result.latitude > 49.0583
      assert result.longitude < -72.02917
    end

    test "ignores a space-A= string that is not an APRS altitude extension" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> "> A=00100 comment"
      result = Object.parse(data)

      assert result[:altitude] == nil
      assert result.comment == "A=00100 comment"
    end

    test "parses a valid negative altitude as a float" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">/A=-00100 comment"
      result = Object.parse(data)

      assert result.data_type == :object
      assert result.altitude == -100.0
    end

    test "leaves a malformed altitude extension in the comment" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">/A=X comment"
      result = Object.parse(data)

      assert result[:altitude] == nil
      assert result.comment == "A=X comment"
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

    test "captures RNG and extracts altitude after it" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">RNG0050/A=000100rest"
      result = Object.parse(data)

      assert result.radiorange == 50
      assert result.altitude == 100.0
      assert result.comment == "rest"
    end

    test "finds altitude late in the comment" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">Prefix/A=001234Test"
      result = Object.parse(data)

      assert result.altitude == 1234.0
      assert result.comment == "PrefixTest"
    end

    test "leaves an out-of-range altitude in the comment" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">/A=500001"
      result = Object.parse(data)

      assert result[:altitude] == nil
      assert result.comment == "/A=500001"
    end

    test "extracts PHG from object comment" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">PHG5132 desc"
      result = Object.parse(data)
      assert result[:phg] == "5132"
    end

    test "strips leading slash delimiter from comment" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> ">/leading-slash"
      result = Object.parse(data)
      assert result[:comment] == "leading-slash"
    end

    test "strips leading space delimiter from comment" do
      data = ";OBJECTNAM*1234567" <> "4903.50N/" <> "07201.75W" <> "> leading-space"
      result = Object.parse(data)
      assert result[:comment] == "leading-space"
    end

    test "parses HHMMSSh timestamps as today's UTC time" do
      started_on = Date.utc_today()
      result = Object.parse(";LEADER   *120000h4903.50N/07201.75W>Test")
      finished_on = Date.utc_today()

      assert is_integer(result.timestamp)
      {:ok, timestamp} = DateTime.from_unix(result.timestamp)

      assert DateTime.to_date(timestamp) in [started_on, finished_on]
      assert DateTime.to_time(timestamp) == ~T[12:00:00]
    end

    test "parses weather for objects using the weather symbol" do
      result = Object.parse(";WEATHER  *120000h4903.50N/07201.75W_220/005g010t050Tail")

      assert result.weather.wind_direction == 220
      assert result.weather.wind_speed == 5
      assert result.weather.wind_gust == 10
      assert result.weather.temperature == 50
      assert result.comment == "Tail"
    end

    test "parses object course and speed with normalized units" do
      result = Object.parse(";LEADER   *120000h4903.50N/07201.75W>088/036Test")

      assert result.course == 88
      assert result.speed == 36.0
      assert result.comment == "Test"
    end
  end
end
