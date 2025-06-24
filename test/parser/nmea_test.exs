defmodule AprsParser.NMEATest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AprsParser.NMEA
  alias AprsParser.Types.ParseError

  describe "parse/1" do
    test "returns not_implemented error for now" do
      assert %ParseError{error_code: :not_implemented} =
               NMEA.parse("$GPRMC,123456,A,4903.50,N,07201.75,W*6A")
    end

    property "always returns not_implemented error for any string" do
      check all s <- StreamData.string(:ascii, min_length: 1, max_length: 30) do
        result = NMEA.parse(s)
        assert %ParseError{error_code: :not_implemented} = result
      end
    end
  end
end
