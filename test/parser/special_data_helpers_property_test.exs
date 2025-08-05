defmodule Aprs.SpecialDataHelpersPropertyTest do
  @moduledoc """
  Property-based tests for special data helpers (PEET logging and invalid/test data).
  Based on real-world patterns from packets.csv
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.SpecialDataHelpers

  describe "PEET logging data" do
    property "handles PEET data with asterisk prefix" do
      check all peet_content <- string(:printable, min_length: 1, max_length: 100) do
        data = "*" <> peet_content

        result = SpecialDataHelpers.parse_peet_logging(data)

        assert result.data_type == :peet_logging
        assert result.peet_data == peet_content
      end
    end

    property "handles PEET data without asterisk" do
      check all peet_content <- string(:printable, min_length: 1, max_length: 100) do
        result = SpecialDataHelpers.parse_peet_logging(peet_content)

        assert result.data_type == :peet_logging
        assert result.peet_data == peet_content
      end
    end

    property "handles empty PEET data" do
      result = SpecialDataHelpers.parse_peet_logging("")
      assert result.data_type == :peet_logging
      assert result.peet_data == ""
    end

    property "handles binary PEET data" do
      check all byte_count <- integer(1..50) do
        bytes = for _ <- 1..byte_count, do: :rand.uniform(255)
        binary_data = :binary.list_to_bin(bytes)

        result = SpecialDataHelpers.parse_peet_logging(binary_data)

        assert result.data_type == :peet_logging
        assert is_binary(result.peet_data)
      end
    end
  end

  describe "invalid/test data" do
    property "handles test data with comma prefix" do
      check all test_content <- string(:printable, min_length: 1, max_length: 100) do
        data = "," <> test_content

        result = SpecialDataHelpers.parse_invalid_test_data(data)

        assert result.data_type == :invalid_test_data
        assert result.test_data == test_content
      end
    end

    property "handles test data without comma" do
      check all test_content <- string(:printable, min_length: 1, max_length: 100) do
        result = SpecialDataHelpers.parse_invalid_test_data(test_content)

        assert result.data_type == :invalid_test_data
        assert result.test_data == test_content
      end
    end

    property "handles empty test data" do
      result = SpecialDataHelpers.parse_invalid_test_data("")
      assert result.data_type == :invalid_test_data
      assert result.test_data == ""
    end

    property "handles special characters in test data" do
      check all special_chars <-
                  list_of(
                    member_of([
                      "!",
                      "@",
                      "#",
                      "$",
                      "%",
                      "^",
                      "&",
                      "*",
                      "(",
                      ")",
                      "[",
                      "]",
                      "{",
                      "}",
                      "|",
                      "\\",
                      ":",
                      ";",
                      "'",
                      "\"",
                      "<",
                      ">",
                      "?",
                      "/"
                    ]),
                    max_length: 20
                  ) do
        data = Enum.join(special_chars)

        result = SpecialDataHelpers.parse_invalid_test_data(data)

        assert result.data_type == :invalid_test_data
        assert result.test_data == data
      end
    end
  end

  describe "real-world patterns" do
    property "handles PEET Bros ultrasonic anemometer data" do
      check all wind_speed <- integer(0..200),
                wind_dir <- integer(0..360),
                temp <- integer(-50..150),
                timestamp <- integer(100_000..999_999) do
        # Simulate PEET Bros format
        peet_data =
          "*#{timestamp}c#{String.pad_leading(to_string(rem(wind_dir, 361)), 3, "0")}s#{String.pad_leading(to_string(wind_speed), 3, "0")}t#{String.pad_leading(to_string(temp), 3, "0")}"

        result = SpecialDataHelpers.parse_peet_logging(peet_data)

        assert result.data_type == :peet_logging
        assert String.starts_with?(result.peet_data, "#{timestamp}c")
      end
    end

    property "handles various invalid packet markers" do
      check all marker <- member_of([",", ",TEST", ",INVALID", ",DEBUG", ",NULL"]),
                content <- string(:alphanumeric, max_length: 50) do
        data = marker <> content

        result = SpecialDataHelpers.parse_invalid_test_data(data)

        assert result.data_type == :invalid_test_data
        # The comma is stripped
        expected_data = String.trim_leading(data, ",")
        assert result.test_data == expected_data
      end
    end

    property "handles mixed binary and text data" do
      check all text_part <- string(:alphanumeric, max_length: 20),
                binary_bytes <- list_of(integer(0..255), max_length: 10),
                more_text <- string(:alphanumeric, max_length: 20) do
        binary_part = :binary.list_to_bin(binary_bytes)
        mixed_data = text_part <> binary_part <> more_text

        # Test with PEET
        peet_result = SpecialDataHelpers.parse_peet_logging("*" <> mixed_data)
        assert peet_result.data_type == :peet_logging
        assert peet_result.peet_data == mixed_data

        # Test with invalid/test
        test_result = SpecialDataHelpers.parse_invalid_test_data("," <> mixed_data)
        assert test_result.data_type == :invalid_test_data
        assert test_result.test_data == mixed_data
      end
    end
  end
end
