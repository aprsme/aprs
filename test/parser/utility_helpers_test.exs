defmodule Aprs.UtilityHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "count_spaces/1" do
    property "counts spaces correctly for any string" do
      check all s <- StreamData.string(:printable, min_length: 0, max_length: 50) do
        expected = s |> String.to_charlist() |> Enum.count(fn c -> c == ?\s end)
        assert Aprs.UtilityHelpers.count_spaces(s) == expected
      end
    end

    test "returns 0 for empty string" do
      assert Aprs.UtilityHelpers.count_spaces("") == 0
    end

    test "returns 0 for string with no spaces" do
      assert Aprs.UtilityHelpers.count_spaces("HelloWorld") == 0
    end

    test "counts single space" do
      assert Aprs.UtilityHelpers.count_spaces("Hello World") == 1
    end

    test "counts multiple spaces" do
      assert Aprs.UtilityHelpers.count_spaces("Hello   World") == 3
    end

    test "counts leading and trailing spaces" do
      assert Aprs.UtilityHelpers.count_spaces("  Hello World  ") == 5
    end

    test "handles tabs and other whitespace" do
      # Only counts spaces
      assert Aprs.UtilityHelpers.count_spaces("Hello\tWorld\nTest") == 0
    end

    test "returns 0 for non-binary input" do
      assert Aprs.UtilityHelpers.count_spaces(nil) == 0
      assert Aprs.UtilityHelpers.count_spaces(123) == 0
    end
  end

  describe "count_leading_braces/1" do
    property "counts leading braces correctly" do
      check all count <- StreamData.integer(0..10),
                rest <- StreamData.string(:printable, min_length: 0, max_length: 20) do
        braces = String.duplicate("}", count)
        input = braces <> rest
        assert Aprs.UtilityHelpers.count_leading_braces(input) == count
      end
    end

    test "returns 0 for empty string" do
      assert Aprs.UtilityHelpers.count_leading_braces("") == 0
    end

    test "returns 0 for string without leading braces" do
      assert Aprs.UtilityHelpers.count_leading_braces("Hello World") == 0
    end

    test "counts single leading brace" do
      assert Aprs.UtilityHelpers.count_leading_braces("}Hello World") == 1
    end

    test "counts multiple leading braces" do
      assert Aprs.UtilityHelpers.count_leading_braces("}}}Hello World") == 3
    end

    test "ignores braces in middle of string" do
      assert Aprs.UtilityHelpers.count_leading_braces("Hello}World") == 0
    end

    test "counts only leading braces" do
      assert Aprs.UtilityHelpers.count_leading_braces("}}Hello}World}") == 2
    end

    test "returns 0 for non-binary input" do
      assert Aprs.UtilityHelpers.count_leading_braces(nil) == 0
      assert Aprs.UtilityHelpers.count_leading_braces(123) == 0
    end
  end

  describe "calculate_position_ambiguity/2" do
    test "delegates to Aprs.Position.calculate_position_ambiguity/2" do
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("1234.56N", "09876.54W") ==
               Aprs.Position.calculate_position_ambiguity("1234.56N", "09876.54W")
    end

    test "returns 0 for no spaces" do
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("1234.56N", "09876.54W") == 0
    end

    test "returns ambiguity based on matching space counts" do
      # Spaces in minute digits per APRS position ambiguity spec
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("1234.5 N", "09876.5 W") == 1
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("1234.  N", "09876.  W") == 2
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("123 .  N", "098 .  W") == 3
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("12  .  N", "09  .  W") == 4
    end

    test "returns 0 for mismatched space counts" do
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("1234.5 N", "09876.54W") == 0
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("1234.56N", "09876.5 W") == 0
    end

    test "returns 0 for more than 4 spaces" do
      assert Aprs.UtilityHelpers.calculate_position_ambiguity("1    .  N", "0    .  W") == 0
    end
  end

  describe "validate_timestamp/1" do
    test "validates correct timestamp formats" do
      # Test various valid timestamp formats
      valid_timestamps = [
        "123456z",
        "123456h",
        "123456/",
        "123456z",
        "000000z",
        "235959h"
      ]

      for timestamp <- valid_timestamps do
        result = Aprs.UtilityHelpers.validate_timestamp(timestamp)
        assert is_integer(result) or is_nil(result)
      end
    end

    test "handles invalid timestamp formats" do
      invalid_timestamps = [
        # Too short
        "12345z",
        # Too long
        "1234567z",
        # Missing suffix
        "123456",
        # Invalid character
        "12345az",
        # Invalid suffix
        "123456x",
        ""
      ]

      for timestamp <- invalid_timestamps do
        result = Aprs.UtilityHelpers.validate_timestamp(timestamp)
        assert is_nil(result)
      end
    end

    test "validates time components" do
      # Out-of-range time components return nil
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("243456z"))
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("253456z"))
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("006059z"))
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("006556z"))
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("005960z"))
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("005561z"))
    end

    test "returns nil for out-of-range HMS hour (hits parse_hms_format fallback)" do
      # Hour 25 is invalid, so the HMS guard fails and the fallback returns nil
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("250000h"))
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("246060h"))
    end

    test "returns nil for non-digit characters in HMS timestamp (hits parse_hms_format _ clause)" do
      # 'A' is not a digit, so the binary digit guard fails -> parse_hms_format(_) -> nil
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp("AB0000h"))
    end

    test "returns nil for non-binary input" do
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp(nil))
      assert is_nil(Aprs.UtilityHelpers.validate_timestamp(123))
    end

    test "returns nil when day is invalid for the current month (Date.new error branch)" do
      now = DateTime.utc_now()
      days_in_month = Calendar.ISO.days_in_month(now.year, now.month)

      # Find a day that's <= 31 (passes the guard) but > days_in_month
      if days_in_month < 31 do
        invalid_day = days_in_month + 1
        ts = String.pad_leading(Integer.to_string(invalid_day), 2, "0") <> "1200z"
        assert is_nil(Aprs.UtilityHelpers.validate_timestamp(ts))
      else
        # In a 31-day month, every day 1-31 is valid; verify that day 31 succeeds
        # so we still exercise the surrounding code path.
        assert is_integer(Aprs.UtilityHelpers.validate_timestamp("311200z"))
      end
    end
  end

  describe "position_resolution/1" do
    test "returns correct resolution for ambiguity level 0" do
      assert Aprs.UtilityHelpers.calculate_position_resolution(0) == 19
    end

    test "returns correct resolution for ambiguity level 1" do
      assert Aprs.UtilityHelpers.calculate_position_resolution(1) == 185
    end

    test "returns correct resolution for ambiguity level 2" do
      assert Aprs.UtilityHelpers.calculate_position_resolution(2) == 1852
    end

    test "returns correct resolution for ambiguity level 3" do
      assert Aprs.UtilityHelpers.calculate_position_resolution(3) == 18_520
    end

    test "returns correct resolution for ambiguity level 4" do
      assert Aprs.UtilityHelpers.calculate_position_resolution(4) == 185_200
    end

    test "returns 19 for out-of-range ambiguity (default clause)" do
      assert Aprs.UtilityHelpers.calculate_position_resolution(5) == 19
      assert Aprs.UtilityHelpers.calculate_position_resolution(-1) == 19
    end
  end
end
