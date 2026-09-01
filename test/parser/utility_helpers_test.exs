defmodule Aprs.UtilityHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.UtilityHelpers

  describe "parse_timestamp/2 day-hour-minute formats" do
    test "parses a timestamp in the current month" do
      now = ~U[2026-09-30 12:00:00Z]

      assert UtilityHelpers.parse_timestamp("092345z", now) ==
               DateTime.to_unix(~U[2026-09-09 23:45:00Z])
    end

    test "accepts the six-byte zulu form" do
      now = ~U[2026-09-30 12:00:00Z]

      assert UtilityHelpers.parse_timestamp("092345", now) ==
               UtilityHelpers.parse_timestamp("092345z", now)
    end

    test "treats local time with an unknown zone as UTC" do
      now = ~U[2026-09-30 12:00:00Z]

      assert UtilityHelpers.parse_timestamp("092345/", now) ==
               UtilityHelpers.parse_timestamp("092345z", now)
    end

    test "uses the previous month when the day is not in the current month" do
      now = ~U[2026-09-01 00:00:00Z]

      assert UtilityHelpers.parse_timestamp("312345z", now) ==
               DateTime.to_unix(~U[2026-08-31 23:45:00Z])
    end

    test "uses the previous month when the current-month timestamp is in the future" do
      now = ~U[2026-09-01 00:00:00Z]

      assert UtilityHelpers.parse_timestamp("302345z", now) ==
               DateTime.to_unix(~U[2026-08-30 23:45:00Z])
    end

    test "rolls back to December from January" do
      now = ~U[2026-01-01 00:00:00Z]

      assert UtilityHelpers.parse_timestamp("312345z", now) ==
               DateTime.to_unix(~U[2025-12-31 23:45:00Z])
    end

    test "returns nil when the timestamp day is absent from both candidate months" do
      assert UtilityHelpers.parse_timestamp("312345z", ~U[2026-05-01 00:00:00Z]) == nil
    end

    test "allows a timestamp up to one hour in the future for clock skew" do
      now = ~U[2026-09-01 00:00:00Z]

      assert UtilityHelpers.parse_timestamp("010030z", now) ==
               DateTime.to_unix(~U[2026-09-01 00:30:00Z])
    end
  end

  describe "parse_timestamp/2 hour-minute-second format" do
    test "uses the previous day for a timestamp beyond the clock-skew allowance" do
      now = ~U[2026-09-02 00:00:05Z]

      assert UtilityHelpers.parse_timestamp("235950h", now) ==
               DateTime.to_unix(~U[2026-09-01 23:59:50Z])
    end

    test "uses the current day for an earlier timestamp" do
      now = ~U[2026-09-02 18:00:00Z]

      assert UtilityHelpers.parse_timestamp("120000h", now) ==
               DateTime.to_unix(~U[2026-09-02 12:00:00Z])
    end

    test "allows a timestamp up to one hour in the future for clock skew" do
      now = ~U[2026-09-02 12:00:00Z]

      assert UtilityHelpers.parse_timestamp("123000h", now) ==
               DateTime.to_unix(~U[2026-09-02 12:30:00Z])
    end
  end

  describe "parse_timestamp/2 validation" do
    test "rejects out-of-range fields" do
      now = ~U[2026-09-02 12:00:00Z]

      assert UtilityHelpers.parse_timestamp("002345z", now) == nil
      assert UtilityHelpers.parse_timestamp("012400z", now) == nil
      assert UtilityHelpers.parse_timestamp("012360z", now) == nil
      assert UtilityHelpers.parse_timestamp("240000h", now) == nil
      assert UtilityHelpers.parse_timestamp("126000h", now) == nil
      assert UtilityHelpers.parse_timestamp("125960h", now) == nil
    end

    test "rejects malformed timestamps" do
      now = ~U[2026-09-02 12:00:00Z]

      assert UtilityHelpers.parse_timestamp("0A2345z", now) == nil
      assert UtilityHelpers.parse_timestamp("092345x", now) == nil
      assert UtilityHelpers.parse_timestamp("09234z", now) == nil
      assert UtilityHelpers.parse_timestamp("09234567", now) == nil
      assert UtilityHelpers.parse_timestamp("", now) == nil
      assert UtilityHelpers.parse_timestamp(nil, now) == nil
    end
  end

  describe "validate_timestamp/1" do
    test "keeps the existing clock-based entry point" do
      assert is_integer(UtilityHelpers.validate_timestamp("120000h"))
    end

    test "returns nil for malformed input" do
      assert UtilityHelpers.validate_timestamp("120000x") == nil
      assert UtilityHelpers.validate_timestamp(nil) == nil
    end
  end

  describe "position_resolution/1" do
    test "returns metres for every supported ambiguity level" do
      assert UtilityHelpers.position_resolution(0) == 18.52
      assert UtilityHelpers.position_resolution(1) == 185.2
      assert UtilityHelpers.position_resolution(2) == 1_852.0
      assert UtilityHelpers.position_resolution(3) == 18_520.0
      assert UtilityHelpers.position_resolution(4) == 185_200.0
    end

    test "uses unambiguous resolution for an unsupported ambiguity level" do
      assert UtilityHelpers.position_resolution(5) == 18.52
      assert UtilityHelpers.position_resolution(-1) == 18.52
      assert UtilityHelpers.position_resolution(nil) == 18.52
    end
  end

  describe "compressed_position_resolution/0" do
    test "returns compressed-coordinate resolution in metres" do
      assert UtilityHelpers.compressed_position_resolution() == 0.291
    end
  end

  describe "nmea_position_resolution/0" do
    test "returns NMEA coordinate resolution in metres" do
      assert UtilityHelpers.nmea_position_resolution() == 0.1852
    end
  end

  describe "count_leading_braces/1" do
    property "counts leading braces correctly" do
      check all count <- StreamData.integer(0..10),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        input = String.duplicate("}", count) <> "x" <> rest
        assert UtilityHelpers.count_leading_braces(input) == count
      end
    end

    test "returns 0 for empty string" do
      assert UtilityHelpers.count_leading_braces("") == 0
    end

    test "returns 0 for string without leading braces" do
      assert UtilityHelpers.count_leading_braces("Hello World") == 0
    end

    test "counts single leading brace" do
      assert UtilityHelpers.count_leading_braces("}Hello World") == 1
    end

    test "counts multiple leading braces" do
      assert UtilityHelpers.count_leading_braces("}}}Hello World") == 3
    end

    test "ignores braces in the middle or at the end" do
      assert UtilityHelpers.count_leading_braces("Hello}World}") == 0
      assert UtilityHelpers.count_leading_braces("}}Hello}World}") == 2
    end

    test "returns 0 for non-binary input" do
      assert UtilityHelpers.count_leading_braces(nil) == 0
      assert UtilityHelpers.count_leading_braces(123) == 0
    end
  end
end
