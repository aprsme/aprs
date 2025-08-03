defmodule Aprs.PHGTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.PHG

  describe "parse/1" do
    test "parses valid PHG string" do
      result = PHG.parse("PHG2360")
      assert result.phg == "2360"
      assert result.data_type == :phg_data
    end

    test "parses valid DFS string" do
      result = PHG.parse("DFS2360")
      assert result.dfs == "2360"
      assert result.data_type == :df_report
    end

    test "returns error for invalid format" do
      result = PHG.parse("invalid")
      assert result.error == "Invalid PHG/DFS format"
      assert result.data_type == :phg_data
    end

    property "handles any string input without crashing" do
      check all s <- StreamData.string(:ascii, min_length: 1, max_length: 30) do
        result = PHG.parse(s)
        assert is_map(result)
        assert result.data_type in [:phg_data, :df_report]
      end
    end
  end
end
