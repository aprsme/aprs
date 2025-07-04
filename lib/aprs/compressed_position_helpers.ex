defmodule Aprs.CompressedPositionHelpers do
  @moduledoc """
  Compressed position helpers for APRS packets.
  """

  # Pre-calculated constants for better performance
  @lat_divisor 456_976
  @lon_divisor 190_463

  @spec convert_compressed_lat(binary()) :: {:ok, float()} | {:error, String.t()}
  def convert_compressed_lat(lat) when is_binary(lat) and byte_size(lat) == 4 do
    [l1, l2, l3, l4] = to_charlist(lat)
    value = calculate_base91_value([l1, l2, l3, l4])
    lat_val = 90 - value / @lat_divisor
    {:ok, clamp_lat(lat_val)}
  end

  def convert_compressed_lat(_), do: {:error, "Invalid compressed latitude"}

  @spec convert_compressed_lon(binary()) :: {:ok, float()} | {:error, String.t()}
  def convert_compressed_lon(lon) when is_binary(lon) and byte_size(lon) == 4 do
    [l1, l2, l3, l4] = to_charlist(lon)
    value = calculate_base91_value([l1, l2, l3, l4])
    lon_val = -180 + value / @lon_divisor
    {:ok, clamp_lon(lon_val)}
  end

  def convert_compressed_lon(_), do: {:error, "Invalid compressed longitude"}

  # Optimized base91 calculation
  defp calculate_base91_value([c1, c2, c3, c4]) do
    (c1 - 33) * 91 * 91 * 91 +
      (c2 - 33) * 91 * 91 +
      (c3 - 33) * 91 +
      (c4 - 33)
  end

  @doc false
  def clamp_lat(lat_val) do
    cond do
      lat_val < -90.0 -> -90.0
      lat_val > 90.0 -> 90.0
      true -> lat_val
    end
  end

  @doc false
  def clamp_lon(lon_val) do
    cond do
      lon_val < -180.0 -> -180.0
      lon_val > 180.0 -> 180.0
      true -> lon_val
    end
  end

  @spec calculate_compressed_ambiguity(binary()) :: integer()
  def calculate_compressed_ambiguity(<<char::utf8, _rest::binary>>) do
    case <<char>> do
      " " -> 0
      "!" -> 1
      "\"" -> 2
      "#" -> 3
      "$" -> 4
      _ -> 0
    end
  end

  def calculate_compressed_ambiguity("") do
    0
  end

  @doc false
  def convert_to_base91(<<value::binary-size(4)>>) do
    [v1, v2, v3, v4] = to_charlist(value)
    calculate_base91_value([v1, v2, v3, v4])
  end

  @spec convert_compressed_cs(binary() | nil) :: map()
  def convert_compressed_cs(cs) when is_binary(cs) and byte_size(cs) == 2 do
    [c, s] = to_charlist(cs)
    _c_val = c - 33
    s_val = s - 33

    cond do
      c == ?Z ->
        %{range: 2 * 1.08 ** s_val}

      c in ?!..?~ and c != ?Z ->
        speed = max(Aprs.Convert.speed(1.08 ** s_val - 1, :knots, :mph), 0.01)
        %{course: s_val * 4, speed: speed}

      true ->
        %{}
    end
  end

  def convert_compressed_cs(_), do: %{}
end
