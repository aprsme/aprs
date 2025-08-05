defmodule Aprs.TelemetryDefinitionsPropertyTest do
  @moduledoc """
  Property-based tests for telemetry definition packets (PARM, UNIT, EQNS, BITS).
  Based on real-world patterns from packets.csv
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Helper to handle parse results
  defp parse_packet(packet) do
    case Aprs.parse(packet) do
      {:ok, result} -> result
      _ -> nil
    end
  end

  describe "telemetry PARM packets" do
    property "handles PARM packets with various parameter names" do
      check all addressee <- string(:alphanumeric, min_length: 1, max_length: 9),
                param_names <- list_of(string(:alphanumeric, max_length: 8), length: 13) do
        padded_addr = String.pad_trailing(addressee, 9)
        params = Enum.join(param_names, ",")

        packet = "TEST>APRS::#{padded_addr}:PARM.#{params}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :message do
          assert String.contains?(result.message || "", "PARM.")
        end
      end
    end

    property "handles real-world PARM patterns" do
      check all channel_type <- member_of(["Indoor", "Outdoor", "Rx", "Tx", "Vin", "Battery", "Solar"]),
                units <-
                  list_of(
                    member_of(["temperature", "humidity", "Traffic", "Packets", "Voltage", "Current", "Power"]),
                    min_length: 1,
                    max_length: 5
                  ),
                digital_labels <-
                  list_of(
                    member_of(["On", "Off", "Hi", "Lo", "Open", "Closed", "Active", "Standby"]),
                    length: 8
                  ) do
        # Build realistic parameter names
        analog_params = Enum.map(units, fn unit -> "#{channel_type} #{unit}" end)

        # Pad to 5 analog channels if needed
        analog_params = analog_params ++ List.duplicate("none", max(0, 5 - length(analog_params)))
        analog_params = Enum.take(analog_params, 5)

        all_params = analog_params ++ digital_labels
        params = Enum.join(all_params, ",")

        packet = "TEST>APRS::TEST     :PARM.#{params}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "telemetry UNIT packets" do
    property "handles UNIT packets with various unit types" do
      check all addressee <- string(:alphanumeric, min_length: 1, max_length: 9),
                analog_units <-
                  list_of(
                    member_of(["[oC]", "[%]", "[V]", "[A]", "[W]", "Pkt", "dBm", "°c", "Volt", "Amp"]),
                    length: 5
                  ),
                digital_units <-
                  list_of(
                    member_of(["On", "Off", "Hi", "Lo", "Open", "Closed", "1", "0"]),
                    length: 8
                  ) do
        padded_addr = String.pad_trailing(addressee, 9)
        units = Enum.join(analog_units ++ digital_units, ",")

        packet = "TEST>APRS::#{padded_addr}:UNIT.#{units}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :message do
          assert String.contains?(result.message || "", "UNIT.")
        end
      end
    end

    property "handles UNIT packets from real patterns" do
      check all has_brackets <- boolean() do
        # Real-world unit patterns
        real_units = [
          ["Volt", "Pkt", "Pkt", "Pcnt", "°c"],
          ["dbm", "V", "A", "W", "%"],
          ["ug/m3", "ug/m3", "ug/m3", "dBm", "V"],
          ["RX Erlang", "TX Erlang", "RXcount/10m", "TXcount/10m", "none1"]
        ]

        analog = Enum.random(real_units)

        # Add brackets if requested
        analog =
          if has_brackets do
            Enum.map(analog, fn u -> "[#{u}]" end)
          else
            analog
          end

        digital = List.duplicate("On", 4) ++ List.duplicate("Hi", 4)
        units = Enum.join(analog ++ digital, ",")

        packet = "TEST>APRS::TEST     :UNIT.#{units}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "telemetry EQNS packets" do
    property "handles EQNS packets with coefficient values" do
      check all addressee <- string(:alphanumeric, min_length: 1, max_length: 9),
                coefficients <-
                  list_of(
                    float(min: -999.0, max: 999.0),
                    length: 15
                  ) do
        padded_addr = String.pad_trailing(addressee, 9)

        # Format coefficients (a, b, c for each of 5 channels)
        eqns =
          Enum.map_join(coefficients, ",", fn c ->
            # Format as string with up to 4 decimal places
            c |> Float.to_string() |> String.split(".") |> hd()
          end)

        packet = "TEST>APRS::#{padded_addr}:EQNS.#{eqns}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :message do
          assert String.contains?(result.message || "", "EQNS.")
        end
      end
    end

    property "handles real-world EQNS patterns" do
      check all scale_type <- member_of([:direct, :scaled, :offset, :complex]) do
        # Common equation patterns
        eqns =
          case scale_type do
            # Direct reading
            :direct -> "0,1,0,0,1,0,0,1,0,0,1,0,0,1,0"
            # Scaled values
            :scaled -> "0,0.1,0,0,0.01,0,0,10,0,0,100,0,0,1,0"
            # With offsets
            :offset -> "0,1,-50,0,1,-273,0,1,100,0,1,0,0,1,0"
            # Complex scaling
            :complex -> "0,-0.2,140,0,0.075,0,0,0.0264,0,0,-1,0,0,0.5,-64"
          end

        packet = "TEST>APRS::TEST     :EQNS.#{eqns}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "telemetry BITS packets" do
    property "handles BITS packets with binary values and project names" do
      check all addressee <- string(:alphanumeric, min_length: 1, max_length: 9),
                bits <- integer(0..255),
                project <- string(:printable, max_length: 30) do
        padded_addr = String.pad_trailing(addressee, 9)

        # Convert to 8-bit binary string
        bit_string = String.pad_leading(Integer.to_string(bits, 2), 8, "0")

        packet = "TEST>APRS::#{padded_addr}:BITS.#{bit_string},#{project}"

        result = parse_packet(packet)

        if result != nil && result.data_type == :message do
          assert String.contains?(result.message || "", "BITS.")
        end
      end
    end

    property "handles real-world BITS patterns" do
      check all all_on <- boolean(),
                project_type <-
                  member_of([
                    "WX3in1P Telemetry",
                    "igate-telem v0.1.2",
                    "Radiobuda SP7QPD-1",
                    "Telemetrie www.i57.dez6",
                    "MiniWX Station"
                  ]) do
        # Real packets often have all bits on (11111111) or specific patterns
        bits = if all_on, do: "11111111", else: "10101010"

        packet = "TEST>APRS::TEST     :BITS.#{bits},#{project_type}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "telemetry definition edge cases" do
    property "handles definitions with missing or extra fields" do
      check all def_type <- member_of(["PARM", "UNIT", "EQNS", "BITS"]),
                field_count <- integer(0..20),
                has_trailing_comma <- boolean() do
        fields = for _ <- 1..field_count, do: "field#{:rand.uniform(100)}"
        field_str = Enum.join(fields, ",")
        field_str = if has_trailing_comma, do: field_str <> ",", else: field_str

        packet = "TEST>APRS::TEST     :#{def_type}.#{field_str}"

        result = parse_packet(packet)
        # Should handle gracefully
        assert result == nil or is_map(result)
      end
    end

    property "handles definitions with special characters" do
      check all def_type <- member_of(["PARM", "UNIT", "EQNS", "BITS"]),
                special_chars <-
                  list_of(
                    member_of(["[", "]", "(", ")", "/", "-", "+", ".", "%", "°"]),
                    max_length: 5
                  ) do
        # Build fields with special characters
        fields =
          for i <- 1..5 do
            base = "field#{i}"
            chars = Enum.join(special_chars)
            "#{base}#{chars}"
          end

        field_str = Enum.join(fields, ",")
        packet = "TEST>APRS::TEST     :#{def_type}.#{field_str}"

        result = parse_packet(packet)
        assert result == nil or is_map(result)
      end
    end
  end
end
