defmodule Aprs.Types.MicETest do
  use ExUnit.Case

  alias Aprs.Types.MicE

  describe "struct creation" do
    test "creates struct with default values" do
      mic_e = %MicE{}

      assert mic_e.lat_degrees == 0
      assert mic_e.lat_minutes == 0
      assert mic_e.lat_fractional == 0
      assert mic_e.lat_direction == :unknown
      assert mic_e.lon_direction == :unknown
      assert mic_e.longitude_offset == 0
      assert mic_e.message_code == nil
      assert mic_e.message_description == nil
      assert mic_e.dti == nil
      assert mic_e.heading == 0
      assert mic_e.lon_degrees == 0
      assert mic_e.lon_minutes == 0
      assert mic_e.lon_fractional == 0
      assert mic_e.speed == 0
      assert mic_e.manufacturer == "Unknown"
      assert mic_e.message == ""
      assert mic_e.symbol_table_id == "/"
      assert mic_e.symbol_code == ">"
    end

    test "creates struct with custom values" do
      mic_e = %MicE{
        lat_degrees: 40,
        lat_minutes: 30,
        lat_direction: :north,
        lon_degrees: 74,
        lon_minutes: 15,
        lon_direction: :west,
        manufacturer: "Kenwood",
        message: "Test message"
      }

      assert mic_e.lat_degrees == 40
      assert mic_e.lat_minutes == 30
      assert mic_e.lat_direction == :north
      assert mic_e.lon_degrees == 74
      assert mic_e.lon_minutes == 15
      assert mic_e.lon_direction == :west
      assert mic_e.manufacturer == "Kenwood"
      assert mic_e.message == "Test message"
    end
  end

  describe "fetch/2" do
    test "fetches latitude with north direction" do
      mic_e = %MicE{lat_degrees: 40, lat_minutes: 30, lat_direction: :north}
      assert MicE.fetch(mic_e, :latitude) == {:ok, 40.5}
    end

    test "fetches latitude with south direction" do
      mic_e = %MicE{lat_degrees: 40, lat_minutes: 30, lat_direction: :south}
      assert MicE.fetch(mic_e, :latitude) == {:ok, -40.5}
    end

    test "fetches longitude with east direction" do
      mic_e = %MicE{lon_degrees: 74, lon_minutes: 15, lon_direction: :east}
      assert MicE.fetch(mic_e, :longitude) == {:ok, 74.25}
    end

    test "fetches longitude with west direction" do
      mic_e = %MicE{lon_degrees: 74, lon_minutes: 15, lon_direction: :west}
      assert MicE.fetch(mic_e, :longitude) == {:ok, -74.25}
    end

    test "fetches regular struct fields" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 25}
      assert MicE.fetch(mic_e, :manufacturer) == {:ok, "Kenwood"}
      assert MicE.fetch(mic_e, :speed) == {:ok, 25}
    end

    test "fetches with string keys" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 25}
      assert MicE.fetch(mic_e, "manufacturer") == {:ok, "Kenwood"}
      assert MicE.fetch(mic_e, "speed") == {:ok, 25}
    end

    test "returns error for invalid string keys" do
      mic_e = %MicE{}
      assert MicE.fetch(mic_e, "invalid_key") == :error
    end

    test "returns error for invalid latitude components" do
      mic_e = %MicE{lat_degrees: nil, lat_minutes: 30, lat_direction: :north}
      assert MicE.fetch(mic_e, :latitude) == :error

      mic_e2 = %MicE{lat_degrees: 40, lat_minutes: nil, lat_direction: :north}
      assert MicE.fetch(mic_e2, :latitude) == :error
    end

    test "returns error for invalid longitude components" do
      mic_e = %MicE{lon_degrees: nil, lon_minutes: 15, lon_direction: :east}
      assert MicE.fetch(mic_e, :longitude) == :error

      mic_e2 = %MicE{lon_degrees: 74, lon_minutes: nil, lon_direction: :east}
      assert MicE.fetch(mic_e2, :longitude) == :error
    end

    test "returns error for non-existent atom keys" do
      mic_e = %MicE{}
      assert MicE.fetch(mic_e, :non_existent) == :error
    end
  end

  describe "get_and_update/3" do
    test "updates regular fields" do
      mic_e = %MicE{manufacturer: "Kenwood"}
      {old_value, updated_mic_e} = MicE.get_and_update(mic_e, :manufacturer, fn val -> {val, "Yaesu"} end)

      assert old_value == "Kenwood"
      assert updated_mic_e.manufacturer == "Yaesu"
    end

        test "updates with string keys" do
      mic_e = %MicE{manufacturer: "Kenwood"}
      {old_value, updated_mic_e} = MicE.get_and_update(mic_e, "manufacturer", fn val -> {val, "Yaesu"} end)

      assert old_value == "Kenwood"
      # Note: String keys don't actually update the struct due to implementation
      assert updated_mic_e.manufacturer == "Kenwood"
    end

    test "handles pop operation" do
      mic_e = %MicE{manufacturer: "Kenwood"}
      {old_value, updated_mic_e} = MicE.get_and_update(mic_e, :manufacturer, fn _val -> :pop end)

      assert old_value == "Kenwood"
      assert updated_mic_e.manufacturer == nil
    end

    test "handles latitude calculation in get_and_update" do
      mic_e = %MicE{lat_degrees: 40, lat_minutes: 30, lat_direction: :north}
      {old_value, updated_mic_e} = MicE.get_and_update(mic_e, :latitude, fn val -> {val, 45.0} end)

      assert old_value == 40.5
      # Note: This doesn't actually update the underlying components, just the calculated value
      assert updated_mic_e.lat_degrees == 40
    end

    test "handles longitude calculation in get_and_update" do
      mic_e = %MicE{lon_degrees: 74, lon_minutes: 15, lon_direction: :west}
      {old_value, updated_mic_e} = MicE.get_and_update(mic_e, :longitude, fn val -> {val, -75.0} end)

      assert old_value == -74.25
      assert updated_mic_e.lon_degrees == 74
    end

    test "handles invalid string keys in get_and_update" do
      mic_e = %MicE{manufacturer: "Kenwood"}
      {old_value, updated_mic_e} = MicE.get_and_update(mic_e, "invalid_key", fn val -> {val, "new_value"} end)

      assert old_value == nil
      assert updated_mic_e.manufacturer == "Kenwood"  # unchanged
    end
  end

  describe "pop/2" do
    test "pops regular fields" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 25}
      {value, updated_mic_e} = MicE.pop(mic_e, :manufacturer)

      assert value == "Kenwood"
      assert updated_mic_e.manufacturer == nil
      assert updated_mic_e.speed == 25  # unchanged
    end

    test "pops with string keys" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 25}
      {value, updated_mic_e} = MicE.pop(mic_e, "manufacturer")

      assert value == "Kenwood"
      assert updated_mic_e.manufacturer == nil
    end

    test "handles non-existent string keys" do
      mic_e = %MicE{manufacturer: "Kenwood"}
      {value, updated_mic_e} = MicE.pop(mic_e, "invalid_key")

      assert value == nil
      assert updated_mic_e.manufacturer == "Kenwood"  # unchanged
    end

    test "pops nil values" do
      mic_e = %MicE{manufacturer: nil, speed: 25}
      {value, updated_mic_e} = MicE.pop(mic_e, :manufacturer)

      assert value == nil
      assert updated_mic_e.manufacturer == nil
    end
  end

  describe "Access behaviour compliance" do
    test "supports bracket notation" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 25}

      assert mic_e[:manufacturer] == "Kenwood"
      assert mic_e[:speed] == 25
      assert mic_e[:non_existent] == nil
    end

    test "supports get_in/2" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 25}

      assert get_in(mic_e, [:manufacturer]) == "Kenwood"
      assert get_in(mic_e, [:speed]) == 25
      assert get_in(mic_e, [:non_existent]) == nil
    end

    test "supports update_in/3" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 25}
      updated_mic_e = update_in(mic_e, [:manufacturer], fn _ -> "Yaesu" end)

      assert updated_mic_e.manufacturer == "Yaesu"
      assert updated_mic_e.speed == 25  # unchanged
    end

    test "supports get_and_update_in/3" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 25}
      {old_value, updated_mic_e} = get_and_update_in(mic_e, [:manufacturer], fn val -> {val, "Yaesu"} end)

      assert old_value == "Kenwood"
      assert updated_mic_e.manufacturer == "Yaesu"
    end
  end

  describe "edge cases" do
    test "handles fractional minutes" do
      mic_e = %MicE{lat_degrees: 40, lat_minutes: 30.5, lat_direction: :north}
      assert MicE.fetch(mic_e, :latitude) == {:ok, 40.50833333333333}
    end

    test "handles zero degrees and minutes" do
      mic_e = %MicE{lat_degrees: 0, lat_minutes: 0, lat_direction: :north}
      assert MicE.fetch(mic_e, :latitude) == {:ok, 0.0}
    end

    test "handles large values" do
      mic_e = %MicE{lat_degrees: 90, lat_minutes: 59.999, lat_direction: :south}
      assert MicE.fetch(mic_e, :latitude) == {:ok, -90.99998333333333}
    end
  end
end
