defmodule Aprs.PHGHelpersTest do
  use ExUnit.Case

  alias Aprs.PHGHelpers

  describe "parse_phg_power/1" do
    test "parses all valid power values" do
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
      assert PHGHelpers.parse_phg_power(?!) == {nil, "Unknown power: !"}
    end
  end

  describe "parse_phg_height/1" do
    test "parses all valid height values" do
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
      assert PHGHelpers.parse_phg_height(?!) == {nil, "Unknown height: !"}
    end
  end

  describe "parse_phg_gain/1" do
    test "parses all valid gain values" do
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
      assert PHGHelpers.parse_phg_gain(?!) == {nil, "Unknown gain: !"}
    end
  end

  describe "parse_phg_directivity/1" do
    test "parses all valid directivity values" do
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
      assert PHGHelpers.parse_phg_directivity(?!) == {nil, "Unknown directivity: !"}
    end
  end

  describe "parse_df_strength/1" do
    test "parses all valid DF strength values" do
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
      assert PHGHelpers.parse_df_strength(?!) == {nil, "Unknown strength: !"}
    end
  end

  describe "edge cases" do
    test "handles boundary character values" do
      # Test characters just outside the valid ranges
      assert PHGHelpers.parse_phg_power(?/) == {nil, "Unknown power: /"}
      assert PHGHelpers.parse_phg_power(?:) == {nil, "Unknown power: :"}
      assert PHGHelpers.parse_phg_power(?@) == {nil, "Unknown power: @"}

      assert PHGHelpers.parse_phg_height(?/) == {nil, "Unknown height: /"}
      assert PHGHelpers.parse_phg_height(?:) == {nil, "Unknown height: :"}
      assert PHGHelpers.parse_phg_height(?@) == {nil, "Unknown height: @"}

      assert PHGHelpers.parse_phg_gain(?/) == {nil, "Unknown gain: /"}
      assert PHGHelpers.parse_phg_gain(?:) == {nil, "Unknown gain: :"}
      assert PHGHelpers.parse_phg_gain(?@) == {nil, "Unknown gain: @"}

      assert PHGHelpers.parse_phg_directivity(?/) == {nil, "Unknown directivity: /"}
      assert PHGHelpers.parse_phg_directivity(?:) == {nil, "Unknown directivity: :"}
      assert PHGHelpers.parse_phg_directivity(?@) == {nil, "Unknown directivity: @"}

      assert PHGHelpers.parse_df_strength(?/) == {nil, "Unknown strength: /"}
      assert PHGHelpers.parse_df_strength(?:) == {nil, "Unknown strength: :"}
      assert PHGHelpers.parse_df_strength(?@) == {nil, "Unknown strength: @"}
    end

    test "handles special characters" do
      # Test various special characters
      assert PHGHelpers.parse_phg_power(?\s) == {nil, "Unknown power:  "}
      assert PHGHelpers.parse_phg_power(?\n) == {nil, "Unknown power: \n"}
      assert PHGHelpers.parse_phg_power(?\t) == {nil, "Unknown power: \t"}

      assert PHGHelpers.parse_phg_height(?\s) == {nil, "Unknown height:  "}
      assert PHGHelpers.parse_phg_height(?\n) == {nil, "Unknown height: \n"}
      assert PHGHelpers.parse_phg_height(?\t) == {nil, "Unknown height: \t"}

      assert PHGHelpers.parse_phg_gain(?\s) == {nil, "Unknown gain:  "}
      assert PHGHelpers.parse_phg_gain(?\n) == {nil, "Unknown gain: \n"}
      assert PHGHelpers.parse_phg_gain(?\t) == {nil, "Unknown gain: \t"}

      assert PHGHelpers.parse_phg_directivity(?\s) == {nil, "Unknown directivity:  "}
      assert PHGHelpers.parse_phg_directivity(?\n) == {nil, "Unknown directivity: \n"}
      assert PHGHelpers.parse_phg_directivity(?\t) == {nil, "Unknown directivity: \t"}

      assert PHGHelpers.parse_df_strength(?\s) == {nil, "Unknown strength:  "}
      assert PHGHelpers.parse_df_strength(?\n) == {nil, "Unknown strength: \n"}
      assert PHGHelpers.parse_df_strength(?\t) == {nil, "Unknown strength: \t"}
    end
  end

  describe "integration scenarios" do
    test "typical PHG parsing scenario" do
      # Simulate parsing a PHG string like "PHG5132"
      power_char = ?5
      height_char = ?1
      gain_char = ?3
      directivity_char = ?2

      {power, power_desc} = PHGHelpers.parse_phg_power(power_char)
      {height, height_desc} = PHGHelpers.parse_phg_height(height_char)
      {gain, gain_desc} = PHGHelpers.parse_phg_gain(gain_char)
      {directivity, directivity_desc} = PHGHelpers.parse_phg_directivity(directivity_char)

      assert power == 36
      assert power_desc == "36 watts"
      assert height == 20
      assert height_desc == "20 feet"
      assert gain == 3
      assert gain_desc == "3 dB"
      assert directivity == 90
      assert directivity_desc == "90° E"
    end

    test "DF strength parsing scenario" do
      # Simulate parsing a DF strength value
      strength_char = ?7
      {strength, strength_desc} = PHGHelpers.parse_df_strength(strength_char)

      assert strength == 7
      assert strength_desc == "21 dB above S0"
    end
  end
end
