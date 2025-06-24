defmodule Aprs.CompressedPositionHelpers do
  @moduledoc """
  Compressed position helpers for APRS packets.
  """

  # Pre-calculated constants for better performance
  @lat_divisor 380_926
  @lon_divisor 190_463

  @spec convert_compressed_lat(binary()) :: {:ok, float()} | {:error, String.t()}
  def convert_compressed_lat(lat) when is_binary(lat) and byte_size(lat) == 4 do
    [l1, l2, l3, l4] = to_charlist(lat)
    value = calculate_base91_value([l1, l2, l3, l4])
    {:ok, 90 - value / @lat_divisor}
  end

  def convert_compressed_lat(_), do: {:error, "Invalid compressed latitude"}

  @spec convert_compressed_lon(binary()) :: {:ok, float()} | {:error, String.t()}
  def convert_compressed_lon(lon) when is_binary(lon) and byte_size(lon) == 4 do
    [l1, l2, l3, l4] = to_charlist(lon)
    value = calculate_base91_value([l1, l2, l3, l4])
    {:ok, -180 + value / @lon_divisor}
  end

  def convert_compressed_lon(_), do: {:error, "Invalid compressed longitude"}

  # Optimized base91 calculation
  defp calculate_base91_value([c1, c2, c3, c4]) do
    (c1 - 33) * 91 * 91 * 91 +
      (c2 - 33) * 91 * 91 +
      (c3 - 33) * 91 +
      (c4 - 33)
  end

  @spec calculate_compressed_ambiguity(String.t()) :: integer()
  def calculate_compressed_ambiguity(compression_type) do
    case compression_type do
      " " -> 0
      "!" -> 1
      "\"" -> 2
      "#" -> 3
      "$" -> 4
      _ -> 0
    end
  end

  @doc false
  def convert_to_base91(<<value::binary-size(4)>>) do
    [v1, v2, v3, v4] = to_charlist(value)
    calculate_base91_value([v1, v2, v3, v4])
  end

  @spec convert_compressed_cs(binary()) :: map()
  def convert_compressed_cs(cs) do
    [c, s] = to_charlist(cs)
    c = c - 33
    s = s - 33

    case c do
      x when x in ?!..?z ->
        %{course: s * 4, speed: Aprs.Convert.speed(1.08 ** s - 1, :knots, :mph)}

      ?Z ->
        %{range: 2 * 1.08 ** s}

      _ ->
        %{}
    end
  end
end
