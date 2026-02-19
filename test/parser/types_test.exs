defmodule Aprs.TypesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Types.MicE
  alias Aprs.Types.Packet
  alias Aprs.Types.ParseError
  alias Aprs.Types.Position

  describe "Position.from_aprs/2" do
    test "parses valid APRS lat/lon strings" do
      result = Position.from_aprs("3339.13N", "11759.13W")
      assert_in_delta result.latitude, 33.652167, 0.000001
      assert_in_delta result.longitude, -117.9855, 0.000001
      result2 = Position.from_aprs("1234.70S", "04540.70E")
      assert_in_delta result2.latitude, -12.578333, 0.000001
      assert_in_delta result2.longitude, 45.678333, 0.000001
    end

    test "returns nils for invalid strings" do
      assert %{latitude: nil, longitude: nil} = Position.from_aprs("bad", "data")
    end
  end

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

  describe "struct creation" do
    test "can create Packet, Position, and ParseError structs" do
      p =
        struct(Packet,
          id: "1",
          sender: "A",
          path: "B",
          destination: "C",
          information_field: "D",
          data_type: :foo,
          base_callsign: "E",
          ssid: "0",
          data_extended: nil,
          received_at: nil
        )

      assert p.id == "1"
      pos = struct(Position, latitude: 1.0, longitude: 2.0)
      assert pos.latitude == 1.0
      err = struct(ParseError, error_code: :bad, error_message: "fail", raw_data: "oops")
      assert err.error_code == :bad
    end
  end
end
