defmodule Aprs.TelemetryHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.TelemetryHelpers

  doctest TelemetryHelpers

  describe "parse_coefficient/1" do
    property "returns a float or the original coefficient string" do
      check all coefficient <-
                  StreamData.one_of([
                    StreamData.float(min: -1000.0, max: 1000.0),
                    StreamData.integer(-1000..1000),
                    StreamData.string(:printable, min_length: 1, max_length: 10)
                  ]) do
        result = coefficient |> to_string() |> TelemetryHelpers.parse_coefficient()

        assert is_float(result) or is_binary(result)
      end
    end

    test "parses decimal, integer, and scientific coefficients as floats" do
      assert TelemetryHelpers.parse_coefficient("123.45") == 123.45
      assert TelemetryHelpers.parse_coefficient("-12") == -12.0
      assert TelemetryHelpers.parse_coefficient("1.23e4") == 12_300.0
      assert TelemetryHelpers.parse_coefficient("1.23E-4") == 0.000123
    end

    test "returns the original string when it cannot parse a coefficient" do
      assert TelemetryHelpers.parse_coefficient("abc") == "abc"
      assert TelemetryHelpers.parse_coefficient("$123.45") == "$123.45"
      assert TelemetryHelpers.parse_coefficient("") == ""
    end

    test "preserves the existing partial numeric parsing behavior" do
      assert TelemetryHelpers.parse_coefficient("12.34abc") == 12.34
      assert TelemetryHelpers.parse_coefficient("123.45°") == 123.45
    end
  end

  test "does not export the removed telemetry parsing helpers" do
    Code.ensure_loaded!(TelemetryHelpers)

    refute function_exported?(TelemetryHelpers, :parse_telemetry_sequence, 1)
    refute function_exported?(TelemetryHelpers, :parse_analog_values, 1)
    refute function_exported?(TelemetryHelpers, :parse_digital_values, 1)
  end
end
