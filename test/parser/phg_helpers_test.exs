defmodule Aprs.PHGHelpersTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.PHGHelpers

  describe "parse_phg_power/1" do
    test "parses valid power values" do
      assert PHGHelpers.parse_phg_power(?0) == {1, "1 watt"}
      assert PHGHelpers.parse_phg_power(?1) == {4, "4 watts"}
      assert PHGHelpers.parse_phg_power(?2) == {9, "9 watts"}
      assert PHGHelpers.parse_phg_power(?3) == {16, "16 watts"}
      assert PHGHelpers.parse_phg_power(?4) == {25, "25 watts"}
      assert PHGHelpers.parse_phg_power(?5) == {36, "36 watts"}
      assert PHGHelpers.parse_phg_power(?6) == {49, "49 watts"}
      assert PHGHelpers.parse_phg_power(?7) == {64, "64 watts"}
      assert PHGHelpers.parse_phg_power(?8) == {81, "81 watts"}
      assert PHGHelpers.parse_phg_power(?9) == {81, "81 watts"}
    end

    test "handles invalid power values" do
      assert PHGHelpers.parse_phg_power(?A) == {nil, "Unknown power: A"}
      assert PHGHelpers.parse_phg_power(?Z) == {nil, "Unknown power: Z"}
      assert PHGHelpers.parse_phg_power(?@) == {nil, "Unknown power: @"}
      assert PHGHelpers.parse_phg_power(255) == {nil, "Unknown power: " <> <<255>>}
    end

    property "power values follow square pattern for digits 0-8" do
      check all digit <- StreamData.integer(?0..?8) do
        {power, _description} = PHGHelpers.parse_phg_power(digit)
        digit_val = digit - ?0
        expected_power = (digit_val + 1) * (digit_val + 1)
        assert power == expected_power
      end
    end

    test "power descriptions are correctly formatted" do
      {power, description} = PHGHelpers.parse_phg_power(?0)
      assert power == 1
      assert description == "1 watt"

      {power, description} = PHGHelpers.parse_phg_power(?1)
      assert power == 4
      assert description == "4 watts"
    end
  end

  describe "parse_phg_height/1" do
    test "parses valid height values" do
      assert PHGHelpers.parse_phg_height(?0) == {10, "10 feet"}
      assert PHGHelpers.parse_phg_height(?1) == {20, "20 feet"}
      assert PHGHelpers.parse_phg_height(?2) == {40, "40 feet"}
      assert PHGHelpers.parse_phg_height(?3) == {80, "80 feet"}
      assert PHGHelpers.parse_phg_height(?4) == {160, "160 feet"}
      assert PHGHelpers.parse_phg_height(?5) == {320, "320 feet"}
      assert PHGHelpers.parse_phg_height(?6) == {640, "640 feet"}
      assert PHGHelpers.parse_phg_height(?7) == {1280, "1280 feet"}
      assert PHGHelpers.parse_phg_height(?8) == {2560, "2560 feet"}
      assert PHGHelpers.parse_phg_height(?9) == {5120, "5120 feet"}
    end

    test "handles invalid height values" do
      assert PHGHelpers.parse_phg_height(?A) == {nil, "Unknown height: A"}
      assert PHGHelpers.parse_phg_height(?Z) == {nil, "Unknown height: Z"}
      assert PHGHelpers.parse_phg_height(?@) == {nil, "Unknown height: @"}
    end

    property "height values follow power-of-2 pattern for digits 0-9" do
      check all digit <- StreamData.integer(?0..?9) do
        {height, _description} = PHGHelpers.parse_phg_height(digit)
        digit_val = digit - ?0
        expected_height = 10 * :math.pow(2, digit_val)
        assert height == round(expected_height)
      end
    end

    test "height descriptions are correctly formatted" do
      {height, description} = PHGHelpers.parse_phg_height(?0)
      assert height == 10
      assert description == "10 feet"

      {height, description} = PHGHelpers.parse_phg_height(?9)
      assert height == 5120
      assert description == "5120 feet"
    end
  end

  describe "parse_phg_gain/1" do
    test "parses valid gain values" do
      assert PHGHelpers.parse_phg_gain(?0) == {0, "0 dB"}
      assert PHGHelpers.parse_phg_gain(?1) == {1, "1 dB"}
      assert PHGHelpers.parse_phg_gain(?2) == {2, "2 dB"}
      assert PHGHelpers.parse_phg_gain(?3) == {3, "3 dB"}
      assert PHGHelpers.parse_phg_gain(?4) == {4, "4 dB"}
      assert PHGHelpers.parse_phg_gain(?5) == {5, "5 dB"}
      assert PHGHelpers.parse_phg_gain(?6) == {6, "6 dB"}
      assert PHGHelpers.parse_phg_gain(?7) == {7, "7 dB"}
      assert PHGHelpers.parse_phg_gain(?8) == {8, "8 dB"}
      assert PHGHelpers.parse_phg_gain(?9) == {9, "9 dB"}
    end

    test "handles invalid gain values" do
      assert PHGHelpers.parse_phg_gain(?A) == {nil, "Unknown gain: A"}
      assert PHGHelpers.parse_phg_gain(?Z) == {nil, "Unknown gain: Z"}
      assert PHGHelpers.parse_phg_gain(?@) == {nil, "Unknown gain: @"}
    end

    property "gain values match digit values for 0-9" do
      check all digit <- StreamData.integer(?0..?9) do
        {gain, _description} = PHGHelpers.parse_phg_gain(digit)
        digit_val = digit - ?0
        assert gain == digit_val
      end
    end

    test "gain descriptions are correctly formatted" do
      {gain, description} = PHGHelpers.parse_phg_gain(?0)
      assert gain == 0
      assert description == "0 dB"

      {gain, description} = PHGHelpers.parse_phg_gain(?9)
      assert gain == 9
      assert description == "9 dB"
    end
  end

  describe "parse_phg_directivity/1" do
    test "parses valid directivity values" do
      assert PHGHelpers.parse_phg_directivity(?0) == {360, "Omni"}
      assert PHGHelpers.parse_phg_directivity(?1) == {45, "45° NE"}
      assert PHGHelpers.parse_phg_directivity(?2) == {90, "90° E"}
      assert PHGHelpers.parse_phg_directivity(?3) == {135, "135° SE"}
      assert PHGHelpers.parse_phg_directivity(?4) == {180, "180° S"}
      assert PHGHelpers.parse_phg_directivity(?5) == {225, "225° SW"}
      assert PHGHelpers.parse_phg_directivity(?6) == {270, "270° W"}
      assert PHGHelpers.parse_phg_directivity(?7) == {315, "315° NW"}
      assert PHGHelpers.parse_phg_directivity(?8) == {360, "360° N"}
      assert PHGHelpers.parse_phg_directivity(?9) == {nil, "Undefined"}
    end

    test "handles invalid directivity values" do
      assert PHGHelpers.parse_phg_directivity(?A) == {nil, "Unknown directivity: A"}
      assert PHGHelpers.parse_phg_directivity(?Z) == {nil, "Unknown directivity: Z"}
      assert PHGHelpers.parse_phg_directivity(?@) == {nil, "Unknown directivity: @"}
    end

    test "directivity values follow 45-degree pattern for digits 1-8" do
      expected_angles = [45, 90, 135, 180, 225, 270, 315, 360]

      for {digit, expected_angle} <- Enum.zip(?1..?8, expected_angles) do
        {angle, _description} = PHGHelpers.parse_phg_directivity(digit)
        assert angle == expected_angle
      end
    end

    test "directivity descriptions include compass directions" do
      {angle, description} = PHGHelpers.parse_phg_directivity(?1)
      assert angle == 45
      assert description == "45° NE"

      {angle, description} = PHGHelpers.parse_phg_directivity(?4)
      assert angle == 180
      assert description == "180° S"
    end

    test "special cases for directivity" do
      # Omni case
      {angle, description} = PHGHelpers.parse_phg_directivity(?0)
      assert angle == 360
      assert description == "Omni"

      # Undefined case
      {angle, description} = PHGHelpers.parse_phg_directivity(?9)
      assert angle == nil
      assert description == "Undefined"
    end
  end

  describe "parse_df_strength/1" do
    test "parses valid DF strength values" do
      assert PHGHelpers.parse_df_strength(?0) == {0, "0 dB"}
      assert PHGHelpers.parse_df_strength(?1) == {1, "3 dB above S0"}
      assert PHGHelpers.parse_df_strength(?2) == {2, "6 dB above S0"}
      assert PHGHelpers.parse_df_strength(?3) == {3, "9 dB above S0"}
      assert PHGHelpers.parse_df_strength(?4) == {4, "12 dB above S0"}
      assert PHGHelpers.parse_df_strength(?5) == {5, "15 dB above S0"}
      assert PHGHelpers.parse_df_strength(?6) == {6, "18 dB above S0"}
      assert PHGHelpers.parse_df_strength(?7) == {7, "21 dB above S0"}
      assert PHGHelpers.parse_df_strength(?8) == {8, "24 dB above S0"}
      assert PHGHelpers.parse_df_strength(?9) == {9, "27 dB above S0"}
    end

    test "handles invalid DF strength values" do
      assert PHGHelpers.parse_df_strength(?A) == {nil, "Unknown strength: A"}
      assert PHGHelpers.parse_df_strength(?Z) == {nil, "Unknown strength: Z"}
      assert PHGHelpers.parse_df_strength(?@) == {nil, "Unknown strength: @"}
    end

    property "DF strength values match digit values for 0-9" do
      check all digit <- StreamData.integer(?0..?9) do
        {strength, _description} = PHGHelpers.parse_df_strength(digit)
        digit_val = digit - ?0
        assert strength == digit_val
      end
    end

    test "DF strength descriptions follow 3dB pattern" do
      {strength, description} = PHGHelpers.parse_df_strength(?0)
      assert strength == 0
      assert description == "0 dB"

      {strength, description} = PHGHelpers.parse_df_strength(?1)
      assert strength == 1
      assert description == "3 dB above S0"

      {strength, description} = PHGHelpers.parse_df_strength(?9)
      assert strength == 9
      assert description == "27 dB above S0"
    end

    property "DF strength descriptions follow correct dB pattern" do
      check all digit <- StreamData.integer(?1..?9) do
        {strength, description} = PHGHelpers.parse_df_strength(digit)
        digit_val = digit - ?0
        expected_db = digit_val * 3
        assert strength == digit_val
        assert description == "#{expected_db} dB above S0"
      end
    end
  end

  describe "error handling" do
    test "all functions handle non-ASCII characters" do
      non_ascii_char = 200

      assert {nil, _} = PHGHelpers.parse_phg_power(non_ascii_char)
      assert {nil, _} = PHGHelpers.parse_phg_height(non_ascii_char)
      assert {nil, _} = PHGHelpers.parse_phg_gain(non_ascii_char)
      assert {nil, _} = PHGHelpers.parse_phg_directivity(non_ascii_char)
      assert {nil, _} = PHGHelpers.parse_df_strength(non_ascii_char)
    end

    test "all functions handle boundary values" do
      # Test just outside valid range
      assert {nil, _} = PHGHelpers.parse_phg_power(?0 - 1)
      assert {nil, _} = PHGHelpers.parse_phg_power(?9 + 1)

      assert {nil, _} = PHGHelpers.parse_phg_height(?0 - 1)
      assert {nil, _} = PHGHelpers.parse_phg_height(?9 + 1)

      assert {nil, _} = PHGHelpers.parse_phg_gain(?0 - 1)
      assert {nil, _} = PHGHelpers.parse_phg_gain(?9 + 1)

      assert {nil, _} = PHGHelpers.parse_phg_directivity(?0 - 1)
      assert {nil, _} = PHGHelpers.parse_phg_directivity(?9 + 1)

      assert {nil, _} = PHGHelpers.parse_df_strength(?0 - 1)
      assert {nil, _} = PHGHelpers.parse_df_strength(?9 + 1)
    end
  end
end
