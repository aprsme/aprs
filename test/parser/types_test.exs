defmodule Aprs.TypesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Types.MicE
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

  describe "MicE.fetch/2 with string key" do
    test "returns error for non-existent atom key passed as string" do
      # Triggers ArgumentError rescue when String.to_existing_atom fails
      mic_e = struct(MicE, [])
      result = MicE.fetch(mic_e, "this_key_definitely_does_not_exist_anywhere_12345")
      assert result == :error
    end

    test "fetches a valid atom key passed as a string" do
      mic_e = %MicE{speed: 45}
      result = MicE.fetch(mic_e, "speed")
      assert result == {:ok, 45}
    end
  end
end
