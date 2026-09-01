defmodule Aprs.TypesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Types.Position

  describe "Position.from_decimal/2" do
    property "returns a map with the same lat/lon as input" do
      check all lat <- StreamData.filter(StreamData.float(), &(&1 >= -90.0 and &1 <= 90.0)),
                lon <- StreamData.filter(StreamData.float(), &(&1 >= -180.0 and &1 <= 180.0)) do
        result = Position.from_decimal(lat, lon)
        assert_in_delta result.latitude, lat, 0.000001
        assert_in_delta result.longitude, lon, 0.000001
      end
    end
  end
end
