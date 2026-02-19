defmodule Aprs.TelemetryFromCommentTest do
  use ExUnit.Case, async: true

  alias Aprs.TelemetryFromComment

  describe "extract_telemetry_from_comment/1" do
    test "extracts telemetry from a comment with pipe-enclosed data" do
      comment = "Hello |!!AB| World"
      {telemetry, cleaned} = TelemetryFromComment.extract_telemetry_from_comment(comment)
      assert is_map(telemetry)
      assert is_binary(cleaned)
    end

    test "returns nil telemetry when no telemetry pattern present" do
      comment = "No telemetry here"
      {telemetry, cleaned} = TelemetryFromComment.extract_telemetry_from_comment(comment)
      assert telemetry == nil
      assert cleaned == comment
    end

    test "returns nil telemetry for empty string" do
      {telemetry, cleaned} = TelemetryFromComment.extract_telemetry_from_comment("")
      assert telemetry == nil
      assert cleaned == ""
    end

    test "handles non-binary input (fallback clause)" do
      {telemetry, original} = TelemetryFromComment.extract_telemetry_from_comment(nil)
      assert telemetry == nil
      assert original == nil

      {telemetry2, original2} = TelemetryFromComment.extract_telemetry_from_comment(123)
      assert telemetry2 == nil
      assert original2 == 123
    end
  end

  describe "parse_base91_telemetry/1" do
    test "parses valid 2-character base91 string" do
      # Both chars must be in range 33-123 (excluding 124)
      result = TelemetryFromComment.parse_base91_telemetry("!!")
      assert result == 0

      result = TelemetryFromComment.parse_base91_telemetry("AB")
      assert is_integer(result)
    end

    test "returns nil for wrong-size input (fallback clause)" do
      assert TelemetryFromComment.parse_base91_telemetry("") == nil
      assert TelemetryFromComment.parse_base91_telemetry("A") == nil
      assert TelemetryFromComment.parse_base91_telemetry("ABC") == nil
    end

    test "returns nil for non-binary input" do
      assert TelemetryFromComment.parse_base91_telemetry(nil) == nil
      assert TelemetryFromComment.parse_base91_telemetry(123) == nil
    end
  end
end
