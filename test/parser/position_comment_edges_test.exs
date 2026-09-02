defmodule Aprs.PositionCommentEdgesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.Object
  alias Aprs.PositionComment

  @object_head ";LEADER   *092345z4903.50N/07201.75W>"

  describe "parse/1 without a comment" do
    test "a position with no comment is returned untouched" do
      position = %{data_type: :item, latitude: 1.0}

      assert PositionComment.parse(position) == position
    end
  end

  describe "course and speed" do
    test "a course inside the compass range is extracted" do
      object = Object.parse(@object_head <> "088/036Text")

      assert object.course == 88
      assert object.speed == 36.0
      assert object.comment == "Text"
    end

    test "a course over 360 degrees is not a course and stays in the comment" do
      object = Object.parse(@object_head <> "999/036Text")

      assert object.comment == "999/036Text"
      refute Map.has_key?(object, :course)
      refute Map.has_key?(object, :speed)
    end

    property "three digits are a course only when they are a compass bearing" do
      check all course <- integer(0..999),
                speed <- integer(0..999) do
        field = pad(course) <> "/" <> pad(speed)
        object = Object.parse(@object_head <> field <> "Text")

        if course <= 360 do
          assert object.course in 1..360
          assert object.speed == speed * 1.0
          assert object.comment == "Text"
        else
          assert object.comment == field <> "Text"
          refute Map.has_key?(object, :course)
        end
      end
    end
  end

  describe "altitude" do
    test "six digits after the marker are an altitude" do
      object = Object.parse(@object_head <> "/A=001234 tail")

      assert object.altitude == 1234.0
      assert object.comment == "tail"
    end

    test "seven digits after the marker are not an altitude" do
      object = Object.parse(@object_head <> "/A=1234567 tail")

      assert object.comment == "A=1234567 tail"
      refute Map.has_key?(object, :altitude)
    end

    property "an altitude marker is honoured only for five or six in-range digits" do
      check all digits <- integer(1..9),
                value <- string(?0..?9, length: digits) do
        object = Object.parse(@object_head <> "/A=" <> value <> " tail")

        cond do
          digits in 5..6 and String.to_integer(value) <= 500_000 ->
            assert object.altitude == String.to_integer(value) * 1.0
            assert object.comment == "tail"

          digits in 5..6 ->
            assert object.comment == "/A=" <> value <> " tail"
            refute Map.has_key?(object, :altitude)

          true ->
            assert object.comment == "A=" <> value <> " tail"
            refute Map.has_key?(object, :altitude)
        end
      end
    end
  end

  describe "four digit markers" do
    test "PHG with four digits is extracted" do
      object = Object.parse(@object_head <> "PHG5360 tail")

      assert object.phg == "5360"
      assert object.comment == "tail"
    end

    test "PHG followed by a fifth digit is not a PHG value" do
      object = Object.parse(@object_head <> "PHG12345 tail")

      assert object.phg == nil
      assert object.comment == "PHG12345 tail"
    end

    test "PHG followed by letters is not a PHG value" do
      object = Object.parse(@object_head <> "PHGab tail padding")

      assert object.phg == nil
      assert object.comment == "PHGab tail padding"
    end

    test "RNG with four digits is a radio range" do
      object = Object.parse(@object_head <> "RNG0050 tail")

      assert object.radiorange == 50
      assert object.comment == "tail"
    end

    test "RNG followed by a fifth digit is not a radio range" do
      object = Object.parse(@object_head <> "RNG12345 tail")

      refute Map.has_key?(object, :radiorange)
      assert object.comment == "RNG12345 tail"
    end
  end

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(3, "0")
end
