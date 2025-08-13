defmodule Aprs.CompressedPositionHelpers do
  @moduledoc """
  Compressed position helpers for APRS packets.
  """

  import Bitwise

  # Pre-calculated constants for better performance
  @lat_divisor 380_926
  @lon_divisor 190_463

  @spec convert_compressed_lat(binary()) :: {:ok, float()} | {:error, String.t()}
  def convert_compressed_lat(lat) when is_binary(lat) and byte_size(lat) == 4 do
    case safe_to_charlist(lat) do
      {:ok, [l1, l2, l3, l4]}
      when l1 >= 33 and l1 <= 126 and
             l2 >= 33 and l2 <= 126 and
             l3 >= 33 and l3 <= 126 and
             l4 >= 33 and l4 <= 126 ->
        value = calculate_base91_value([l1, l2, l3, l4])
        lat_val = 90 - value / @lat_divisor
        {:ok, clamp_lat(lat_val)}

      {:ok, _} ->
        {:error, "Invalid compressed latitude - contains non-ASCII characters"}

      {:error, _} ->
        {:error, "Invalid compressed latitude - invalid encoding"}
    end
  end

  def convert_compressed_lat(_), do: {:error, "Invalid compressed latitude"}

  @spec convert_compressed_lon(binary()) :: {:ok, float()} | {:error, String.t()}
  def convert_compressed_lon(lon) when is_binary(lon) and byte_size(lon) == 4 do
    case safe_to_charlist(lon) do
      {:ok, [l1, l2, l3, l4]}
      when l1 >= 33 and l1 <= 126 and
             l2 >= 33 and l2 <= 126 and
             l3 >= 33 and l3 <= 126 and
             l4 >= 33 and l4 <= 126 ->
        value = calculate_base91_value([l1, l2, l3, l4])
        lon_val = -180 + value / @lon_divisor
        {:ok, clamp_lon(lon_val)}

      {:ok, _} ->
        {:error, "Invalid compressed longitude - contains non-ASCII characters"}

      {:error, _} ->
        {:error, "Invalid compressed longitude - invalid encoding"}
    end
  end

  def convert_compressed_lon(_), do: {:error, "Invalid compressed longitude"}

  # Safe conversion to charlist that handles invalid UTF-8
  defp safe_to_charlist(binary) do
    {:ok, to_charlist(binary)}
  rescue
    UnicodeConversionError -> {:error, :invalid_utf8}
  end

  # Optimized base91 calculation
  defp calculate_base91_value([c1, c2, c3, c4]) do
    (c1 - 33) * 91 * 91 * 91 +
      (c2 - 33) * 91 * 91 +
      (c3 - 33) * 91 +
      (c4 - 33)
  end

  @doc false
  def clamp_lat(lat_val) do
    lat_val
    |> max(-90.0)
    |> min(90.0)
  end

  @doc false
  def clamp_lon(lon_val) do
    lon_val
    |> max(-180.0)
    |> min(180.0)
  end

  # Map of resolution values to ambiguity levels
  @resolution_to_ambiguity %{
    # No ambiguity
    0 => 0,
    # 0.1 minute
    1 => 1,
    # 1 minute
    2 => 2,
    # 10 minutes
    3 => 3,
    # 1 degree
    4 => 4
  }

  @doc """
  Calculate position resolution (ambiguity) from the compression type byte.

  In compressed format, the compression type byte encodes:
  - Bits 0-1: GPS fix type/NMEA source
  - Bits 2-4: Position resolution
  - Bit 5: Old/Current GPS data

  Position resolution values:
  - 0: No resolution specified (full precision)
  - 1: 0.1' (about 600 feet)
  - 2: 1' (about 0.01 degree)
  - 3: 10' (about 0.1 degree)  
  - 4: 1 degree
  """
  @spec calculate_compressed_ambiguity(binary()) :: integer()
  def calculate_compressed_ambiguity(<<char::8, _rest::binary>>) do
    # The compression type is offset by 33 to make it printable ASCII
    # Special case for space character which is 0x20 (32)
    type_value = calculate_type_value(char)

    # Extract bits 2-4 for position resolution
    # Shift right by 2 bits and mask with 0b111 (7)
    resolution = type_value >>> 2 &&& 0x07

    # Map to standard ambiguity levels (0-4), default to 0 for invalid values
    Map.get(@resolution_to_ambiguity, resolution, 0)
  end

  def calculate_compressed_ambiguity("") do
    0
  end

  @doc """
  Parse the compression type byte to extract all encoded information.

  Returns a map with:
  - gps_fix_type: NMEA source/GPS fix type (0-3)
  - position_resolution: Position ambiguity level (0-4)
  - old_gps_data: Whether this is old GPS data
  - aprs_messaging: APRS messaging capability (bit 6)
  """
  @spec parse_compression_type(binary()) :: map()
  def parse_compression_type(<<char::8, _rest::binary>>) do
    # The compression type is offset by 33 to make it printable ASCII
    # Special case for space character which is 0x20 (32)
    type_value = calculate_type_value(char)

    # Extract individual bit fields
    # Bits 0-1
    gps_fix = type_value &&& 0x03
    # Bits 2-4
    resolution = type_value >>> 2 &&& 0x07
    # Bit 5
    old_data = type_value >>> 5 &&& 0x01
    # Bit 6 - APRS messaging capability
    messaging = type_value >>> 6 &&& 0x01

    %{
      gps_fix_type: decode_gps_fix_type(gps_fix),
      position_resolution: map_resolution_to_ambiguity(resolution),
      old_gps_data: old_data == 1,
      aprs_messaging: messaging
    }
  end

  def parse_compression_type("") do
    %{
      gps_fix_type: :unknown,
      position_resolution: 0,
      old_gps_data: false,
      aprs_messaging: 0
    }
  end

  @spec calculate_type_value(integer()) :: integer()
  defp calculate_type_value(char) when char < 33, do: 0
  defp calculate_type_value(char), do: char - 33

  @spec decode_gps_fix_type(integer()) :: atom()
  # Compressed from other source
  defp decode_gps_fix_type(0), do: :other
  # From GLL or GGA NMEA sentence
  defp decode_gps_fix_type(1), do: :gll_gga
  # From RMC NMEA sentence  
  defp decode_gps_fix_type(2), do: :rmc
  # Unknown/reserved
  defp decode_gps_fix_type(3), do: :unknown
  defp decode_gps_fix_type(_), do: :unknown

  @spec map_resolution_to_ambiguity(integer()) :: integer()
  # No ambiguity
  defp map_resolution_to_ambiguity(0), do: 0
  # 0.1 minute
  defp map_resolution_to_ambiguity(1), do: 1
  # 1 minute  
  defp map_resolution_to_ambiguity(2), do: 2
  # 10 minutes
  defp map_resolution_to_ambiguity(3), do: 3
  # 1 degree
  defp map_resolution_to_ambiguity(4), do: 4
  # Default to no ambiguity for invalid values
  defp map_resolution_to_ambiguity(_), do: 0

  @doc false
  def convert_to_base91(<<value::binary-size(4)>>) do
    [v1, v2, v3, v4] = to_charlist(value)
    calculate_base91_value([v1, v2, v3, v4])
  end

  @spec convert_compressed_cs(binary() | nil) :: map()
  # Check for DAO extension pattern
  def convert_compressed_cs("&!"), do: %{}

  def convert_compressed_cs(<<c, s>> = cs) when is_binary(cs) do
    s_val = s - 33
    decode_course_speed(c, s_val)
  end

  def convert_compressed_cs(_), do: %{}

  @spec decode_course_speed(integer(), integer()) :: map()
  defp decode_course_speed(?Z, s_val) do
    %{range: 2 * 1.08 ** s_val}
  end

  defp decode_course_speed(c, s_val) when c in ?!..?~ and c != ?Z do
    speed = max(Aprs.Convert.speed(1.08 ** s_val - 1, :knots, :mph), 0.01)
    %{course: s_val * 4, speed: speed}
  end

  defp decode_course_speed(_, _), do: %{}
end
