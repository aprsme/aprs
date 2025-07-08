defmodule Aprs.Types.MicETest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Types.MicE

  describe "MicE struct" do
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
        lat_degrees: 34,
        lat_minutes: 20.5,
        lat_direction: :north,
        lon_degrees: 118,
        lon_minutes: 15.2,
        lon_direction: :west,
        speed: 45,
        heading: 180,
        manufacturer: "Kenwood",
        message: "Test message"
      }

      assert mic_e.lat_degrees == 34
      assert mic_e.lat_minutes == 20.5
      assert mic_e.lat_direction == :north
      assert mic_e.lon_degrees == 118
      assert mic_e.lon_minutes == 15.2
      assert mic_e.lon_direction == :west
      assert mic_e.speed == 45
      assert mic_e.heading == 180
      assert mic_e.manufacturer == "Kenwood"
      assert mic_e.message == "Test message"
    end
  end

  describe "Access behaviour - fetch/2" do
    test "fetches latitude from components" do
      mic_e = %MicE{
        lat_degrees: 34,
        lat_minutes: 20.5,
        lat_direction: :north
      }

      assert {:ok, 34.34166666666667} = MicE.fetch(mic_e, :latitude)
    end

    test "fetches negative latitude for south direction" do
      mic_e = %MicE{
        lat_degrees: 34,
        lat_minutes: 20.5,
        lat_direction: :south
      }

      assert {:ok, -34.34166666666667} = MicE.fetch(mic_e, :latitude)
    end

    test "fetches longitude from components" do
      mic_e = %MicE{
        lon_degrees: 118,
        lon_minutes: 15.2,
        lon_direction: :east
      }

      assert {:ok, 118.25333333333333} = MicE.fetch(mic_e, :longitude)
    end

    test "fetches negative longitude for west direction" do
      mic_e = %MicE{
        lon_degrees: 118,
        lon_minutes: 15.2,
        lon_direction: :west
      }

      assert {:ok, -118.25333333333333} = MicE.fetch(mic_e, :longitude)
    end

    test "returns error for invalid latitude components" do
      mic_e = %MicE{lat_degrees: nil, lat_minutes: 20.5}
      assert :error = MicE.fetch(mic_e, :latitude)

      mic_e = %MicE{lat_degrees: 34, lat_minutes: nil}
      assert :error = MicE.fetch(mic_e, :latitude)
    end

    test "returns error for invalid longitude components" do
      mic_e = %MicE{lon_degrees: nil, lon_minutes: 15.2}
      assert :error = MicE.fetch(mic_e, :longitude)

      mic_e = %MicE{lon_degrees: 118, lon_minutes: nil}
      assert :error = MicE.fetch(mic_e, :longitude)
    end

    test "fetches regular struct fields" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 45}

      assert {:ok, "Kenwood"} = MicE.fetch(mic_e, :manufacturer)
      assert {:ok, 45} = MicE.fetch(mic_e, :speed)
    end

    test "fetches fields using string keys" do
      mic_e = %MicE{manufacturer: "Kenwood", speed: 45}

      assert {:ok, "Kenwood"} = MicE.fetch(mic_e, "manufacturer")
      assert {:ok, 45} = MicE.fetch(mic_e, "speed")
    end

    test "returns error for non-existent string keys" do
      mic_e = %MicE{}
      assert :error = MicE.fetch(mic_e, "non_existent_key")
    end

    test "returns error for non-existent atom keys" do
      mic_e = %MicE{}
      assert :error = MicE.fetch(mic_e, :non_existent_key)
    end
  end

  describe "Access behaviour - get_and_update/3" do
    test "gets and updates latitude" do
      mic_e = %MicE{
        lat_degrees: 34,
        lat_minutes: 20.5,
        lat_direction: :north
      }

      {old_value, _new_struct} = MicE.get_and_update(mic_e, :latitude, fn val -> {val, val + 1} end)
      assert old_value == 34.34166666666667
    end

    test "gets and updates longitude" do
      mic_e = %MicE{
        lon_degrees: 118,
        lon_minutes: 15.2,
        lon_direction: :west
      }

      {old_value, _new_struct} = MicE.get_and_update(mic_e, :longitude, fn val -> {val, val + 1} end)
      assert old_value == -118.25333333333333
    end

    test "gets and updates regular fields" do
      mic_e = %MicE{speed: 45}

      {old_value, new_struct} = MicE.get_and_update(mic_e, :speed, fn val -> {val, val + 10} end)
      assert old_value == 45
      assert new_struct.speed == 55
    end

    test "gets and updates with string keys" do
      mic_e = %MicE{manufacturer: "Kenwood"}

      {old_value, new_struct} = MicE.get_and_update(mic_e, "manufacturer", fn val -> {val, "Yaesu"} end)
      assert old_value == "Kenwood"
      # The implementation puts the string key directly, so we need to check for it differently
      assert Map.get(new_struct, "manufacturer") == "Yaesu"
    end

    test "handles non-existent string keys gracefully" do
      mic_e = %MicE{}

      {old_value, new_struct} = MicE.get_and_update(mic_e, "non_existent", fn val -> {val, "new"} end)
      assert old_value == nil
      # The implementation puts the string key directly, so the struct will be modified
      assert Map.get(new_struct, "non_existent") == "new"
    end

    test "handles :pop return value" do
      mic_e = %MicE{speed: 45}

      {old_value, new_struct} = MicE.get_and_update(mic_e, :speed, fn _val -> :pop end)
      assert old_value == 45
      assert new_struct.speed == nil
    end
  end

  describe "Access behaviour - pop/2" do
    test "pops atom keys" do
      mic_e = %MicE{speed: 45}

      {old_value, new_struct} = MicE.pop(mic_e, :speed)
      assert old_value == 45
      assert new_struct.speed == nil
    end

    test "pops string keys" do
      mic_e = %MicE{manufacturer: "Kenwood"}

      {old_value, new_struct} = MicE.pop(mic_e, "manufacturer")
      assert old_value == "Kenwood"
      assert new_struct.manufacturer == nil
    end

    test "handles non-existent string keys" do
      mic_e = %MicE{}

      {old_value, new_struct} = MicE.pop(mic_e, "non_existent")
      assert old_value == nil
      assert new_struct == mic_e
    end
  end

  describe "property tests" do
    property "latitude calculation is consistent" do
      check all degrees <- StreamData.integer(0..90),
                minutes <- StreamData.float(min: 0.0, max: 59.999),
                direction <- StreamData.member_of([:north, :south]) do
        mic_e = %MicE{
          lat_degrees: degrees,
          lat_minutes: minutes,
          lat_direction: direction
        }

        {:ok, lat} = MicE.fetch(mic_e, :latitude)
        expected = degrees + minutes / 60.0
        expected = if direction == :south, do: -expected, else: expected

        assert_in_delta lat, expected, 0.0001
      end
    end

    property "longitude calculation is consistent" do
      check all degrees <- StreamData.integer(0..180),
                minutes <- StreamData.float(min: 0.0, max: 59.999),
                direction <- StreamData.member_of([:east, :west]) do
        mic_e = %MicE{
          lon_degrees: degrees,
          lon_minutes: minutes,
          lon_direction: direction
        }

        {:ok, lon} = MicE.fetch(mic_e, :longitude)
        expected = degrees + minutes / 60.0
        expected = if direction == :west, do: -expected, else: expected

        assert_in_delta lon, expected, 0.0001
      end
    end
  end
end
