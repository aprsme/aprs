defmodule Aprs.StatusTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Status

  describe "parse/1" do
    test "returns a status map for valid input" do
      assert Status.parse(">Test status message") == %{
               data_type: :status,
               status_text: "Test status message"
             }
    end

    test "extracts a leading status timestamp" do
      result = Status.parse("092345zNet control on 146.52")

      assert is_integer(result.timestamp)
      assert result.status_text == "Net control on 146.52"
    end

    test "extracts a leading six-character grid locator and symbol" do
      assert Status.parse("IO91SX/- My status") == %{
               data_type: :status,
               grid_locator: "IO91SX",
               status_text: "My status",
               symbol_code: "-",
               symbol_table_id: "/"
             }
    end

    test "extracts a leading four-character grid locator and symbol" do
      assert Status.parse("IO91/- Four-character grid") == %{
               data_type: :status,
               grid_locator: "IO91",
               status_text: "Four-character grid",
               symbol_code: "-",
               symbol_table_id: "/"
             }
    end

    test "extracts trailing beam heading and power" do
      assert Status.parse("Hello^B7") == %{
               beam_heading: 110,
               beam_power: 640,
               data_type: :status,
               status_text: "Hello"
             }
    end

    test "extracts timestamp, grid locator, symbol, and beam data in order" do
      result = Status.parse("092345zIO91SX/- Net control^B7")

      assert is_integer(result.timestamp)

      assert Map.delete(result, :timestamp) == %{
               beam_heading: 110,
               beam_power: 640,
               data_type: :status,
               grid_locator: "IO91SX",
               status_text: "Net control",
               symbol_code: "-",
               symbol_table_id: "/"
             }
    end

    property "always returns a map with :data_type == :status for any string" do
      check all s <- StreamData.string(:ascii, min_length: 1, max_length: 30) do
        result = Status.parse(s)
        assert is_map(result)
        assert result[:data_type] == :status
      end
    end
  end
end
