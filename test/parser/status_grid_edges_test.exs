defmodule Aprs.StatusGridEdgesTest do
  use ExUnit.Case, async: true

  alias Aprs.Status

  describe "status timestamps" do
    test "a timestamp shaped field that is not a real time stays in the status text" do
      assert Status.parse(">999999zStatus text") == %{
               data_type: :status,
               status_text: "999999zStatus text"
             }
    end

    test "a real timestamp is removed from the status text" do
      assert %{timestamp: timestamp, status_text: "Status text"} = Status.parse(">092345zStatus text")

      assert is_integer(timestamp)
    end
  end

  describe "status grid locators" do
    test "a grid locator with no symbol after it is only status text" do
      assert Status.parse(">EM48") == %{data_type: :status, status_text: "EM48"}
    end

    test "a four character locator followed by a symbol is a grid locator" do
      assert Status.parse(">EM48/-") == %{
               data_type: :status,
               status_text: "",
               grid_locator: "EM48",
               symbol_table_id: "/",
               symbol_code: "-"
             }
    end

    test "a six character locator followed by a symbol is a grid locator" do
      assert %{grid_locator: "EM48ss", symbol_table_id: "/", symbol_code: "-"} = Status.parse(">EM48ss/-")
    end
  end
end
