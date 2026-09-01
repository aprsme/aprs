defmodule Aprs.TelemetryDefinitionsPropertyTest do
  @moduledoc """
  Property-based tests for telemetry definition packets (PARM, UNIT, EQNS, BITS).
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Telemetry
  alias Aprs.TelemetryHelpers

  property "PARM definitions preserve every non-empty parameter name" do
    check all names <-
                list_of(
                  string(:alphanumeric, min_length: 1, max_length: 8),
                  min_length: 1,
                  max_length: 13
                ) do
      fields = Enum.join(names, ",")
      expected = %{data_type: :telemetry_parameters, parameter_names: names, raw_data: fields}

      assert Telemetry.parse_definition("PARM." <> fields) == expected
      assert Telemetry.parse_definition(":PARM." <> fields) == expected
    end
  end

  property "UNIT definitions preserve every non-empty unit" do
    unit =
      member_of([
        "[oC]",
        "[%]",
        "[V]",
        "[A]",
        "[W]",
        "Pkt",
        "dBm",
        "Volt",
        "Amp"
      ])

    check all units <- list_of(unit, min_length: 1, max_length: 13) do
      fields = Enum.join(units, ",")

      assert Telemetry.parse_definition("UNIT." <> fields) == %{
               data_type: :telemetry_units,
               units: units,
               raw_data: fields
             }
    end
  end

  property "EQNS definitions discard only coefficients in a trailing partial equation" do
    coefficient = member_of(["-999", "-1.5", "0", "0.1", "1", "42.25", "999"])

    check all coefficients <- list_of(coefficient, max_length: 17) do
      fields = Enum.join(coefficients, ",")

      expected_equations =
        coefficients
        |> Enum.chunk_every(3, 3, :discard)
        |> Enum.map(fn [a, b, c] ->
          %{
            a: TelemetryHelpers.parse_coefficient(a),
            b: TelemetryHelpers.parse_coefficient(b),
            c: TelemetryHelpers.parse_coefficient(c)
          }
        end)

      assert Telemetry.parse_definition("EQNS." <> fields) == %{
               data_type: :telemetry_equations,
               equations: expected_equations,
               raw_data: fields
             }
    end
  end

  property "BITS definitions return an eight-character sense list and project names" do
    check all value <- integer(0..255),
              projects <-
                list_of(
                  string(:alphanumeric, min_length: 1, max_length: 12),
                  max_length: 4
                ) do
      bits = value |> Integer.to_string(2) |> String.pad_leading(8, "0")
      rest = Enum.join([bits | projects], ",")

      assert Telemetry.parse_definition(":BITS." <> rest) == %{
               data_type: :telemetry_bits,
               bits_sense: String.to_charlist(bits),
               project_names: projects,
               raw_data: rest
             }
    end
  end

  property "unknown definition names are rejected" do
    check all name <- string(:alphanumeric, min_length: 1, max_length: 10),
              name not in ["PARM", "UNIT", "EQNS", "BITS"] do
      assert Telemetry.parse_definition(name <> ".value") == nil
      assert Telemetry.parse_definition(":" <> name <> ".value") == nil
    end
  end
end
