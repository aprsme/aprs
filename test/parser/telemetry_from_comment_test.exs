defmodule Aprs.TelemetryFromCommentTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

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
    # Comment filler that cannot contain the "|" telemetry delimiter (0x7C),
    # so the generated telemetry block is the only possible match.
    @filler_chars [?a..?z, ?A..?Z, ?0..?9, ?\s]

    property "extracts the sequence and values and strips the block from the comment" do
      check all prefix <- StreamData.string(@filler_chars, max_length: 10),
                suffix <- StreamData.string(@filler_chars, max_length: 10),
                pairs <- StreamData.list_of(base91_pair(), min_length: 1, max_length: 9) do
        block = Enum.join(pairs)
        comment = prefix <> "|" <> block <> "|" <> suffix

        {telemetry, cleaned} = TelemetryFromComment.extract_telemetry_from_comment(comment)

        [seq_pair | value_pairs] = pairs
        assert telemetry.seq == decode_pair(seq_pair)
        assert telemetry.vals == Enum.map(value_pairs, &decode_pair/1)
        assert length(telemetry.vals) <= 8
        assert cleaned == String.trim(prefix <> suffix)
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
          # Delimiters may be non-base91 characters, so entries can decode to nil.
          assert is_nil(telemetry.seq) or telemetry.seq in 0..8280
          assert Enum.all?(telemetry.vals, &(is_nil(&1) or &1 in 0..8280))
          assert length(telemetry.vals) <= 8
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
end
