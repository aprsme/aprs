defmodule Aprs.TelemetryEdgesTest do
  use ExUnit.Case, async: true

  alias Aprs.Telemetry

  describe "colon prefixed definitions" do
    test "parse/1 accepts an equation definition" do
      assert %{data_type: :telemetry_equations, equations: equations} = Telemetry.parse(":EQNS.0,1,0")

      assert equations == [%{a: 0.0, b: 1.0, c: 0.0}]
    end

    test "parse_definition/1 accepts a unit definition with the colon" do
      assert Telemetry.parse_definition(":UNIT.Volts,Amps") == %{
               data_type: :telemetry_units,
               units: ["Volts", "Amps"],
               raw_data: "Volts,Amps"
             }
    end

    test "parse_definition/1 accepts an equation definition with the colon" do
      assert %{data_type: :telemetry_equations, equations: equations} =
               Telemetry.parse_definition(":EQNS.0,1,0,0,2,0")

      assert equations == [%{a: 0.0, b: 1.0, c: 0.0}, %{a: 0.0, b: 2.0, c: 0.0}]
    end
  end

  describe "digital bits field" do
    test "eight binary digits after five analog values are digital bits" do
      assert %{telemetry: telemetry, mbits: mbits} = Telemetry.parse("T#005,199,000,255,073,123,01010101")

      assert telemetry.bits == "01010101"
      assert mbits == "01010101"
      assert telemetry.vals == [199.0, 0.0, 255.0, 73.0, 123.0]
    end

    test "eight characters that are not binary digits are not digital bits" do
      assert %{telemetry: telemetry} = result = Telemetry.parse("T#005,199,000,255,073,123,01234567")

      assert telemetry.bits == nil
      assert telemetry.vals == [199.0, 0.0, 255.0, 73.0, 123.0]
      refute Map.has_key?(result, :mbits)
    end

    test "a non-binary trailing field in the fifth slot stays an analog value" do
      assert %{telemetry: telemetry} = Telemetry.parse("T#005,199,000,255,073,01234567")

      assert telemetry.bits == nil
      assert telemetry.vals == [199.0, 0.0, 255.0, 73.0, 1_234_567.0]
    end
  end
end
