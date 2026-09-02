defmodule Aprs.FallbackShapesTest do
  @moduledoc """
  Shapes the binary scanners in the fallback paths have to keep accepting, which
  the rest of the suite does not cover: a failed `/A=` marker that is followed
  by a real one, and positions whose degree or minute fields are not the widths
  the spec defines.
  """

  use ExUnit.Case, async: true

  describe "altitude scanning" do
    test "a failed /A= marker does not hide the marker overlapping it" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:!4903.50N/07201.75W-/A=/A=001234 rest")

      assert packet.altitude == 1234.0
      assert packet.comment == "A= rest"
    end

    test "scanning resumes after a marker with too few digits" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:!4903.50N/07201.75W-/A=12 more/A=001234 tail")

      assert packet.altitude == 1234.0
      assert packet.comment == "A=12 more tail"
    end
  end

  describe "loose timestamped position fallback" do
    test "accepts more minute fraction digits than the spec width" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z4903.5678N/07201.7512W-long fraction")

      assert packet.data_type == :timestamped_position_with_message
      assert packet.symboltable == "/"
      assert packet.symbolcode == "-"
      assert packet.comment == "long fraction"
    end

    test "accepts five degree digits of latitude and six of longitude" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z14903.50N/107201.75W-five digit degrees")

      assert packet.data_type == :timestamped_position_with_message
      assert packet.comment == "five digit degrees"
    end

    test "takes any byte but a line feed as the symbol table" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z4903.50N\t07201.75W-tab table")

      assert packet.symboltable == "\t"
      assert packet.latitude == 49.05833333333333
    end

    test "keeps a multi-byte comment intact" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z4903.5678N/07201.7512W-é comment")

      assert packet.comment == "é comment"
    end

    test "rejects a field holding a line feed" do
      assert {:ok, packet} = Aprs.parse("N0CALL>APRS:@092345z4903.5678N/07201.7512W-embedded\nnewline")

      assert packet.data_type == :timestamped_position_error
      assert packet.error == "Invalid timestamped position format"
    end
  end
end
