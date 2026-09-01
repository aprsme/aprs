defmodule Aprs.GuardsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  require Aprs.Guards

  defmodule Helper do
    @moduledoc false
    import Aprs.Guards

    require Aprs.Guards

    def digit?(b) when is_digit(b), do: true
    def digit?(_), do: false

    def minute_tens?(b) when is_minute_tens(b), do: true
    def minute_tens?(_), do: false

    def digit_or_space?(b) when is_digit_or_space(b), do: true
    def digit_or_space?(_), do: false

    def base91?(b) when is_base91(b), do: true
    def base91?(_), do: false

    def alphanumeric?(b) when is_alphanumeric(b), do: true
    def alphanumeric?(_), do: false
  end

  describe "is_digit/1" do
    test "matches ASCII digits 0-9" do
      for b <- ?0..?9, do: assert(Helper.digit?(b))
    end

    test "rejects non-digit bytes" do
      refute Helper.digit?(?A)
      refute Helper.digit?(?z)
      refute Helper.digit?(?\s)
      refute Helper.digit?(?/)
    end

    property "true iff byte is in ?0..?9" do
      check all(b <- StreamData.integer(0..255)) do
        assert Helper.digit?(b) == (b >= ?0 and b <= ?9)
      end
    end
  end

  describe "is_minute_tens/1" do
    test "accepts 0-7 and space" do
      for b <- ?0..?7, do: assert(Helper.minute_tens?(b))
      assert Helper.minute_tens?(?\s)
    end

    test "rejects 8, 9, and others" do
      refute Helper.minute_tens?(?8)
      refute Helper.minute_tens?(?9)
      refute Helper.minute_tens?(?A)
    end
  end

  describe "is_digit_or_space/1" do
    test "accepts digits and space" do
      for b <- ?0..?9, do: assert(Helper.digit_or_space?(b))
      assert Helper.digit_or_space?(?\s)
    end

    test "rejects letters" do
      refute Helper.digit_or_space?(?A)
      refute Helper.digit_or_space?(?-)
    end
  end

  describe "is_base91/1" do
    test "accepts the APRS base-91 range (33..123)" do
      for b <- 33..123, do: assert(Helper.base91?(b))
    end

    test "rejects control chars, high bytes and the out-of-range printables" do
      refute Helper.base91?(0)
      refute Helper.base91?(32)
      refute Helper.base91?(124)
      refute Helper.base91?(126)
      refute Helper.base91?(127)
      refute Helper.base91?(200)
    end
  end

  describe "is_alphanumeric/1" do
    test "accepts upper, lower, digits" do
      for b <- ?a..?z, do: assert(Helper.alphanumeric?(b))
      for b <- ?A..?Z, do: assert(Helper.alphanumeric?(b))
      for b <- ?0..?9, do: assert(Helper.alphanumeric?(b))
    end

    test "rejects punctuation and spaces" do
      refute Helper.alphanumeric?(?\s)
      refute Helper.alphanumeric?(?-)
      refute Helper.alphanumeric?(?_)
      refute Helper.alphanumeric?(?/)
    end

    property "matches the expected ranges" do
      check all(b <- StreamData.integer(0..255)) do
        expected =
          (b >= ?a and b <= ?z) or (b >= ?A and b <= ?Z) or (b >= ?0 and b <= ?9)

        assert Helper.alphanumeric?(b) == expected
      end
    end
  end
end
