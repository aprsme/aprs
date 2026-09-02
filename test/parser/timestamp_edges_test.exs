defmodule Aprs.TimestampEdgesTest do
  use ExUnit.Case, async: true

  alias Aprs.UtilityHelpers

  @now ~U[2026-04-15 12:00:00Z]

  describe "hour-minute-second timestamps" do
    test "a field that is not six digits is not a timestamp" do
      assert UtilityHelpers.parse_timestamp("12ab56h", @now) == nil
    end

    test "a time earlier today resolves to today" do
      assert UtilityHelpers.parse_timestamp("120000h", @now) == DateTime.to_unix(~U[2026-04-15 12:00:00Z])
    end
  end

  describe "day-hour-minute timestamps" do
    test "a day that does not exist this month resolves against the previous month" do
      assert UtilityHelpers.parse_timestamp("310000z", @now) == DateTime.to_unix(~U[2026-03-31 00:00:00Z])
    end

    test "a day earlier this month resolves to this month" do
      assert UtilityHelpers.parse_timestamp("140000z", @now) == DateTime.to_unix(~U[2026-04-14 00:00:00Z])
    end

    test "a day later this month resolves against the previous month" do
      assert UtilityHelpers.parse_timestamp("200000z", @now) == DateTime.to_unix(~U[2026-03-20 00:00:00Z])
    end

    test "an impossible day is not a timestamp" do
      assert UtilityHelpers.parse_timestamp("999999z", @now) == nil
    end
  end
end
