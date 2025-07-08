defmodule Aprs.TelemetryHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "parse_telemetry_sequence/1" do
    property "parses valid sequence numbers" do
      check all seq <- StreamData.integer(0..999) do
        seq_str = to_string(seq)
        result = Aprs.TelemetryHelpers.parse_telemetry_sequence(seq_str)
        assert result == seq
      end
    end

    test "parses valid sequence numbers" do
      assert Aprs.TelemetryHelpers.parse_telemetry_sequence("0") == 0
      assert Aprs.TelemetryHelpers.parse_telemetry_sequence("123") == 123
      assert Aprs.TelemetryHelpers.parse_telemetry_sequence("999") == 999
    end

    test "returns nil for invalid sequence numbers" do
      assert Aprs.TelemetryHelpers.parse_telemetry_sequence("12.34") == 12
    end

    test "handles edge cases" do
      assert Aprs.TelemetryHelpers.parse_telemetry_sequence("000") == 0
      assert Aprs.TelemetryHelpers.parse_telemetry_sequence("001") == 1
      assert Aprs.TelemetryHelpers.parse_telemetry_sequence("999") == 999
    end
  end

  describe "parse_analog_values/1" do
    property "parses list of analog values" do
      check all values <-
                  StreamData.list_of(
                    StreamData.one_of([
                      StreamData.string(:printable, min_length: 0, max_length: 10),
                      StreamData.constant("")
                    ]),
                    min_length: 0,
                    max_length: 10
                  ) do
        result = Aprs.TelemetryHelpers.parse_analog_values(values)
        assert is_list(result)
        assert length(result) == length(values)
      end
    end

    test "parses valid float values" do
      assert Aprs.TelemetryHelpers.parse_analog_values(["123.45"]) == [123.45]
      assert Aprs.TelemetryHelpers.parse_analog_values(["-12.34"]) == [-12.34]
      assert Aprs.TelemetryHelpers.parse_analog_values(["0.0"]) == [0.0]
      assert Aprs.TelemetryHelpers.parse_analog_values(["999.999"]) == [999.999]
    end

    test "parses valid integer values" do
      assert Aprs.TelemetryHelpers.parse_analog_values(["123"]) == [123.0]
      assert Aprs.TelemetryHelpers.parse_analog_values(["-12"]) == [-12.0]
      assert Aprs.TelemetryHelpers.parse_analog_values(["0"]) == [0.0]
      assert Aprs.TelemetryHelpers.parse_analog_values(["999"]) == [999.0]
    end

    test "returns nil for empty string or invalid values" do
      assert Aprs.TelemetryHelpers.parse_analog_values([""]) == [nil]
      assert Aprs.TelemetryHelpers.parse_analog_values(["abc"]) == [nil]
      assert Aprs.TelemetryHelpers.parse_analog_values(["12.34abc"]) == [12.34]
      assert Aprs.TelemetryHelpers.parse_analog_values(["abc12.34"]) == [nil]
    end

    test "handles edge cases" do
      assert Aprs.TelemetryHelpers.parse_analog_values(["0"]) == [0.0]
      assert Aprs.TelemetryHelpers.parse_analog_values(["0.0"]) == [0.0]
      assert Aprs.TelemetryHelpers.parse_analog_values(["000"]) == [0.0]
      assert Aprs.TelemetryHelpers.parse_analog_values(["000.000"]) == [0.0]
    end
  end

  describe "parse_coefficient/1" do
    property "parses valid coefficients" do
      check all coeff <-
                  StreamData.one_of([
                    StreamData.filter(StreamData.float(), &(&1 >= -1000.0 and &1 <= 1000.0)),
                    StreamData.integer(-1000..1000),
                    StreamData.string(:printable, min_length: 1, max_length: 10)
                  ]) do
        coeff_str = to_string(coeff)
        result = Aprs.TelemetryHelpers.parse_coefficient(coeff_str)
        assert is_number(result) or is_binary(result)
      end
    end

    test "parses valid float coefficients" do
      assert Aprs.TelemetryHelpers.parse_coefficient("123.45") == 123.45
      assert Aprs.TelemetryHelpers.parse_coefficient("-12.34") == -12.34
      assert Aprs.TelemetryHelpers.parse_coefficient("0.0") == 0.0
      assert Aprs.TelemetryHelpers.parse_coefficient("999.999") == 999.999
    end

    test "parses valid integer coefficients" do
      assert Aprs.TelemetryHelpers.parse_coefficient("123") == 123
      assert Aprs.TelemetryHelpers.parse_coefficient("-12") == -12
      assert Aprs.TelemetryHelpers.parse_coefficient("0") == 0
      assert Aprs.TelemetryHelpers.parse_coefficient("999") == 999
    end

    test "returns original string for invalid coefficients" do
      assert Aprs.TelemetryHelpers.parse_coefficient("abc") == "abc"
      assert Aprs.TelemetryHelpers.parse_coefficient("12.34abc") == 12.34
      assert Aprs.TelemetryHelpers.parse_coefficient("abc12.34") == "abc12.34"
      assert Aprs.TelemetryHelpers.parse_coefficient("") == ""
    end

    test "handles edge cases" do
      assert Aprs.TelemetryHelpers.parse_coefficient("0") == 0
      assert Aprs.TelemetryHelpers.parse_coefficient("0.0") == 0.0
      assert Aprs.TelemetryHelpers.parse_coefficient("000") == 0
      assert Aprs.TelemetryHelpers.parse_coefficient("000.000") == 0.0
    end

    test "handles scientific notation" do
      assert Aprs.TelemetryHelpers.parse_coefficient("1.23e4") == 12_300.0
      assert Aprs.TelemetryHelpers.parse_coefficient("1.23E-4") == 0.000123
    end

    test "handles special characters" do
      assert Aprs.TelemetryHelpers.parse_coefficient("12.34%") == 12.34
      assert Aprs.TelemetryHelpers.parse_coefficient("$123.45") == "$123.45"
      assert Aprs.TelemetryHelpers.parse_coefficient("123.45°") == 123.45
    end
  end

  describe "integration tests" do
    test "parses complete telemetry data" do
      # Simulate parsing a complete telemetry packet
      sequence = "123"
      analog_values = ["100", "200", "300", "400", "500"]
      digital_values = ["10101010", "11110000"]

      seq_result = Aprs.TelemetryHelpers.parse_telemetry_sequence(sequence)
      analog_result = Aprs.TelemetryHelpers.parse_analog_values(analog_values)
      digital_result = Aprs.TelemetryHelpers.parse_digital_values(digital_values)

      assert seq_result == 123
      assert analog_result == [100.0, 200.0, 300.0, 400.0, 500.0]

      assert digital_result == [
               true,
               false,
               true,
               false,
               true,
               false,
               true,
               false,
               true,
               true,
               true,
               true,
               false,
               false,
               false,
               false
             ]
    end

    test "handles real-world telemetry examples" do
      # Example from APRS specification
      sequence = "001"
      analog_values = ["123", "456", "789", "012", "345"]
      digital_values = ["11111111", "00000000"]

      seq_result = Aprs.TelemetryHelpers.parse_telemetry_sequence(sequence)
      analog_result = Aprs.TelemetryHelpers.parse_analog_values(analog_values)
      digital_result = Aprs.TelemetryHelpers.parse_digital_values(digital_values)

      assert seq_result == 1
      assert analog_result == [123.0, 456.0, 789.0, 12.0, 345.0]

      assert digital_result == [
               true,
               true,
               true,
               true,
               true,
               true,
               true,
               true,
               false,
               false,
               false,
               false,
               false,
               false,
               false,
               false
             ]
    end

    test "handles malformed telemetry data" do
      sequence = "abc"
      analog_values = ["123", "abc", "456", "", "def"]
      digital_values = ["101", "abc", "010", "def"]

      seq_result = Aprs.TelemetryHelpers.parse_telemetry_sequence(sequence)
      analog_result = Aprs.TelemetryHelpers.parse_analog_values(analog_values)
      digital_result = Aprs.TelemetryHelpers.parse_digital_values(digital_values)

      assert seq_result == nil
      assert analog_result == [123.0, nil, 456.0, nil, nil]
      assert is_list(digital_result)
    end

    test "handles empty telemetry data" do
      sequence = ""
      analog_values = []
      digital_values = []

      seq_result = Aprs.TelemetryHelpers.parse_telemetry_sequence(sequence)
      analog_result = Aprs.TelemetryHelpers.parse_analog_values(analog_values)
      digital_result = Aprs.TelemetryHelpers.parse_digital_values(digital_values)

      assert seq_result == nil
      assert analog_result == []
      assert digital_result == []
    end
  end
end
