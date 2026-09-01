defmodule Aprs.TelemetryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Telemetry

  describe "parse/1" do
    test "returns a map with :data_type for valid input" do
      result = Telemetry.parse("T#123,456,789,012,345,678,10101010")

      assert is_map(result)
      assert Map.has_key?(result, :data_type)
    end

    property "always returns a map with :data_type for any string" do
      check all s <- StreamData.string(:ascii, min_length: 1, max_length: 30) do
        result = Telemetry.parse(s)

        assert is_map(result)
        assert Map.has_key?(result, :data_type)
      end
    end

    test "parses five analog values and an optional digital value" do
      result = Telemetry.parse("T#123,1,2,3,4,5,10101010")

      assert result == %{
               data_type: :telemetry,
               mbits: "10101010",
               raw_data: "123,1,2,3,4,5,10101010",
               telemetry: %{
                 seq: "123",
                 vals: [1.0, 2.0, 3.0, 4.0, 5.0],
                 bits: "10101010"
               }
             }
    end

    test "parses one to five analog values without padding missing channels" do
      result = Telemetry.parse("T#123,1,2,3")

      assert result == %{
               data_type: :telemetry,
               raw_data: "123,1,2,3",
               telemetry: %{seq: "123", vals: [1.0, 2.0, 3.0], bits: nil}
             }

      refute Map.has_key?(result, :mbits)

      with_bits = Telemetry.parse("T#124,9,11110000")

      assert with_bits.telemetry == %{
               seq: "124",
               vals: [9.0],
               bits: "11110000"
             }

      assert with_bits.mbits == "11110000"
    end

    test "parses five analog values when the digital value is absent" do
      result = Telemetry.parse("T#123,1,2,3,4,5")

      assert result.telemetry == %{
               seq: "123",
               vals: [1.0, 2.0, 3.0, 4.0, 5.0],
               bits: nil
             }

      refute Map.has_key?(result, :mbits)
    end

    test "keeps the literal Mic-E telemetry sequence" do
      result = Telemetry.parse("T#MIC199,000,000,000,000,00000000")

      assert result.telemetry == %{
               seq: "MIC199",
               vals: [0.0, 0.0, 0.0, 0.0],
               bits: "00000000"
             }

      assert result.mbits == "00000000"
    end

    test "uses nil for unparseable analog values" do
      result = Telemetry.parse("T#001,abc,0.0,12.5")

      assert result.telemetry.vals == [nil, 0.0, 12.5]
    end

    test "keeps sequence-only telemetry as raw data" do
      assert Telemetry.parse("T#123") == %{raw_data: "123", data_type: :telemetry}
    end

    test "parses #-prefixed telemetry when the T is already stripped" do
      result = Telemetry.parse("#123,1,2,3,4,5,10101010")

      assert result.data_type == :telemetry
      assert result.telemetry.seq == "123"
    end

    test "delegates colon-prefixed telemetry definitions" do
      assert Telemetry.parse(":PARM.A,B,C,D,E") == %{
               data_type: :telemetry_parameters,
               parameter_names: ["A", "B", "C", "D", "E"],
               raw_data: "A,B,C,D,E"
             }

      assert Telemetry.parse(":UNIT.V,A,degC").units == ["V", "A", "degC"]
      assert Telemetry.parse(":BITS.101010,foo,bar").project_names == ["foo", "bar"]
    end

    test "parses empty :BITS. definition" do
      assert Telemetry.parse(":BITS.") == %{
               data_type: :telemetry_bits,
               bits_sense: [],
               project_names: [],
               raw_data: ""
             }
    end

    test "parses unknown data as raw telemetry" do
      assert Telemetry.parse("random data") == %{
               data_type: :telemetry,
               raw_data: "random data"
             }
    end
  end

  describe "parse_definition/1" do
    test "accepts definitions with or without a leading colon" do
      expected = %{
        data_type: :telemetry_parameters,
        parameter_names: ["Battery", "Temp", "Light"],
        raw_data: "Battery,Temp,Light"
      }

      assert Telemetry.parse_definition("PARM.Battery,Temp,Light") == expected
      assert Telemetry.parse_definition(":PARM.Battery,Temp,Light") == expected
    end

    test "discards a trailing partial equation" do
      assert Telemetry.parse_definition("EQNS.0,1,2,0,1") == %{
               data_type: :telemetry_equations,
               equations: [%{a: 0.0, b: 1.0, c: 2.0}],
               raw_data: "0,1,2,0,1"
             }
    end

    test "returns nil for an unknown definition" do
      assert Telemetry.parse_definition("UNKNOWN.value") == nil
    end
  end
end
