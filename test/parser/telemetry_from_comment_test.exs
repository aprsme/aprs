defmodule Aprs.TelemetryFromCommentTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.TelemetryFromComment

  describe "extract_telemetry_from_comment/1" do
    test "extracts a sequence and one analog value and removes the block" do
      comment = "Hello |ss11| world"

      assert {telemetry, "Hello  world"} =
               TelemetryFromComment.extract_telemetry_from_comment(comment)

      assert telemetry == %{
               seq: decode_pair("ss"),
               vals: [decode_pair("11")],
               bits: nil
             }
    end

    test "decodes the seventh pair as an eight-bit digital value" do
      analog_pairs = ["!!", "!\"", "!#", "!$", "!%"]
      digital_pair = encode_pair(170)
      comment = "|" <> Enum.join(["!&" | analog_pairs] ++ [digital_pair]) <> "|"

      assert {telemetry, ""} = TelemetryFromComment.extract_telemetry_from_comment(comment)
      assert telemetry.seq == decode_pair("!&")
      assert telemetry.vals == Enum.map(analog_pairs, &decode_pair/1)
      assert telemetry.bits == "10101010"
    end

    test "rejects a nine-pair run and leaves the comment unchanged" do
      comment = "Hello |" <> String.duplicate("!!", 9) <> "| world"

      assert {nil, ^comment} = TelemetryFromComment.extract_telemetry_from_comment(comment)
    end

    test "rejects bytes outside the base91 range and missing closing delimiters" do
      invalid_byte = "before |ss1~| after"
      missing_delimiter = "before |ss11 after"

      assert {nil, ^invalid_byte} =
               TelemetryFromComment.extract_telemetry_from_comment(invalid_byte)

      assert {nil, ^missing_delimiter} =
               TelemetryFromComment.extract_telemetry_from_comment(missing_delimiter)
    end

    test "returns nil telemetry when no telemetry pattern is present" do
      comment = "No telemetry here"

      assert {nil, ^comment} = TelemetryFromComment.extract_telemetry_from_comment(comment)
      assert {nil, ""} = TelemetryFromComment.extract_telemetry_from_comment("")
    end

    test "handles non-binary input" do
      assert {nil, nil} = TelemetryFromComment.extract_telemetry_from_comment(nil)
      assert {nil, 123} = TelemetryFromComment.extract_telemetry_from_comment(123)
    end
  end

  describe "parse_base91_telemetry/1" do
    test "parses valid 2-character base91 string" do
      # Both bytes must be in the inclusive range 33..123.
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

  describe "parse_base91_telemetry/1 properties" do
    # Base91 digits are ASCII 33..123; two digits encode 0..8280.
    @base91_digits Enum.to_list(33..123)

    property "decodes any two base91 digits to (c1 - 33) * 91 + (c2 - 33)" do
      check all c1 <- StreamData.member_of(@base91_digits),
                c2 <- StreamData.member_of(@base91_digits) do
        result = TelemetryFromComment.parse_base91_telemetry(<<c1, c2>>)

        assert result == (c1 - 33) * 91 + (c2 - 33)
        assert result in 0..8280
      end
    end

    property "returns nil unless the input is exactly two bytes" do
      check all bytes <- StreamData.binary(max_length: 8), byte_size(bytes) != 2 do
        assert TelemetryFromComment.parse_base91_telemetry(bytes) == nil
      end
    end

    property "returns nil when either byte falls outside the base91 range" do
      out_of_range = StreamData.filter(StreamData.integer(0..255), &(&1 < 33 or &1 > 123))

      check all bad <- out_of_range,
                good <- StreamData.member_of(@base91_digits),
                swapped <- StreamData.boolean() do
        bytes = if swapped, do: <<good, bad>>, else: <<bad, good>>
        assert TelemetryFromComment.parse_base91_telemetry(bytes) == nil
      end
    end
  end

  describe "extract_telemetry_from_comment/1 properties" do
    @filler_chars [?a..?z, ?A..?Z, ?0..?9, ?\s]

    property "extracts valid blocks containing two to seven base91 pairs" do
      check all prefix <- StreamData.string(@filler_chars, max_length: 10),
                suffix <- StreamData.string(@filler_chars, max_length: 10),
                pairs <- StreamData.list_of(base91_pair(), min_length: 2, max_length: 7) do
        comment = prefix <> "|" <> Enum.join(pairs) <> "|" <> suffix

        assert {telemetry, cleaned} =
                 TelemetryFromComment.extract_telemetry_from_comment(comment)

        [seq_pair | value_pairs] = pairs
        assert telemetry.seq == decode_pair(seq_pair)

        if length(pairs) == 7 do
          {analog_pairs, [digital_pair]} = Enum.split(value_pairs, 5)
          assert telemetry.vals == Enum.map(analog_pairs, &decode_pair/1)
          assert telemetry.bits == to_bits(decode_pair(digital_pair))
        else
          assert telemetry.vals == Enum.map(value_pairs, &decode_pair/1)
          assert telemetry.bits == nil
        end

        assert cleaned == String.trim(prefix <> suffix)
      end
    end

    property "rejects base91 runs longer than seven pairs" do
      check all pairs <- StreamData.list_of(base91_pair(), min_length: 8, max_length: 9) do
        comment = "prefix|" <> Enum.join(pairs) <> "|suffix"

        assert {nil, ^comment} = TelemetryFromComment.extract_telemetry_from_comment(comment)
      end
    end

    property "returns the comment unchanged when it holds no telemetry block" do
      check all comment <- StreamData.string(@filler_chars, max_length: 40) do
        assert {nil, ^comment} = TelemetryFromComment.extract_telemetry_from_comment(comment)
      end
    end

    property "always returns a {telemetry, binary} tuple for any printable comment" do
      check all comment <- StreamData.string(:printable, max_length: 60) do
        {telemetry, cleaned} = TelemetryFromComment.extract_telemetry_from_comment(comment)

        assert is_binary(cleaned)

        if telemetry do
          assert telemetry.seq in 0..8280
          assert Enum.all?(telemetry.vals, &(&1 in 0..8280))
          assert length(telemetry.vals) in 1..5
          assert telemetry.bits == nil or byte_size(telemetry.bits) == 8
        else
          assert cleaned == comment
        end
      end
    end
  end

  defp base91_pair do
    StreamData.string(Enum.to_list(33..123), length: 2)
  end

  defp decode_pair(<<c1, c2>>), do: (c1 - 33) * 91 + (c2 - 33)
  defp encode_pair(value), do: <<div(value, 91) + 33, rem(value, 91) + 33>>

  defp to_bits(value) do
    value
    |> rem(256)
    |> Integer.to_string(2)
    |> String.pad_leading(8, "0")
  end
end
