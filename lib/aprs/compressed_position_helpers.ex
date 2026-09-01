defmodule Aprs.CompressedPositionHelpers do
  @moduledoc """
  Decodes APRS compressed position coordinates, cs pairs, and compression metadata.
  """

  import Aprs.Guards
  import Bitwise

  @lat_divisor 380_926
  @lon_divisor 190_463

  @nmea_sources {:other, :gll, :gga, :rmc}

  @origins {
    :compressed,
    :tnc_btext,
    :software,
    :tbd,
    :kpc3,
    :pico,
    :other_tracker,
    :digipeater_conversion
  }

  @doc """
  Decodes a four-byte base-91 compressed latitude.
  """
  @spec convert_compressed_lat(binary()) :: {:ok, float()} | {:error, String.t()}
  def convert_compressed_lat(lat) when is_binary(lat) and byte_size(lat) == 4 do
    case safe_to_charlist(lat) do
      {:ok, [l1, l2, l3, l4]}
      when is_base91(l1) and is_base91(l2) and is_base91(l3) and is_base91(l4) ->
        validate_latitude(90 - calculate_base91_value([l1, l2, l3, l4]) / @lat_divisor)

      {:ok, _} ->
        {:error, "Invalid compressed latitude - contains non-ASCII characters"}

      {:error, _} ->
        {:error, "Invalid compressed latitude - invalid encoding"}
    end
  end

  def convert_compressed_lat(_), do: {:error, "Invalid compressed latitude"}

  @doc """
  Decodes a four-byte base-91 compressed longitude.
  """
  @spec convert_compressed_lon(binary()) :: {:ok, float()} | {:error, String.t()}
  def convert_compressed_lon(lon) when is_binary(lon) and byte_size(lon) == 4 do
    case safe_to_charlist(lon) do
      {:ok, [l1, l2, l3, l4]}
      when is_base91(l1) and is_base91(l2) and is_base91(l3) and is_base91(l4) ->
        validate_longitude(-180 + calculate_base91_value([l1, l2, l3, l4]) / @lon_divisor)

      {:ok, _} ->
        {:error, "Invalid compressed longitude - contains non-ASCII characters"}

      {:error, _} ->
        {:error, "Invalid compressed longitude - invalid encoding"}
    end
  end

  def convert_compressed_lon(_), do: {:error, "Invalid compressed longitude"}

  @spec validate_latitude(float()) :: {:ok, float()} | {:error, String.t()}
  defp validate_latitude(latitude) when latitude >= -90 and latitude <= 90, do: {:ok, latitude}
  defp validate_latitude(_latitude), do: {:error, "Invalid compressed latitude - out of range"}

  @spec validate_longitude(float()) :: {:ok, float()} | {:error, String.t()}
  defp validate_longitude(longitude) when longitude >= -180 and longitude <= 180, do: {:ok, longitude}
  defp validate_longitude(_longitude), do: {:error, "Invalid compressed longitude - out of range"}

  @spec safe_to_charlist(binary()) :: {:ok, charlist()} | {:error, :invalid_utf8}
  defp safe_to_charlist(binary) do
    {:ok, to_charlist(binary)}
  rescue
    UnicodeConversionError -> {:error, :invalid_utf8}
  end

  @spec calculate_base91_value([non_neg_integer()]) :: non_neg_integer()
  defp calculate_base91_value([c1, c2, c3, c4]) do
    (c1 - 33) * 91 * 91 * 91 +
      (c2 - 33) * 91 * 91 +
      (c3 - 33) * 91 +
      (c4 - 33)
  end

  @doc """
  Decodes the GPS fix age, NMEA source, and encoder origin from a compression type byte.

  An empty value, or a leading byte below the base-91 offset, decodes as zero.
  """
  @spec parse_compression_type(binary()) :: %{
          gps_fix: :old | :current,
          nmea_source: :other | :gll | :gga | :rmc,
          origin:
            :compressed
            | :tnc_btext
            | :software
            | :tbd
            | :kpc3
            | :pico
            | :other_tracker
            | :digipeater_conversion
        }
  def parse_compression_type(<<char, _rest::binary>>) do
    char
    |> calculate_type_value()
    |> decode_compression_type()
  end

  def parse_compression_type(""), do: decode_compression_type(0)

  @spec calculate_type_value(integer()) :: non_neg_integer()
  defp calculate_type_value(char) when char < 33, do: 0
  defp calculate_type_value(char), do: char - 33

  @spec decode_compression_type(non_neg_integer()) :: map()
  defp decode_compression_type(type_value) do
    %{
      gps_fix: if((type_value &&& 0x20) == 0, do: :old, else: :current),
      nmea_source: elem(@nmea_sources, type_value >>> 3 &&& 0x03),
      origin: elem(@origins, type_value &&& 0x07)
    }
  end

  @spec gga_compression_type?(binary()) :: boolean()
  defp gga_compression_type?(<<char, _rest::binary>>) do
    type_value = calculate_type_value(char)
    (type_value >>> 3 &&& 0x03) == 0x02
  end

  defp gga_compression_type?(""), do: false

  @doc false
  @spec convert_to_base91(binary()) :: non_neg_integer()
  def convert_to_base91(<<value::binary-size(4)>>) do
    [v1, v2, v3, v4] = to_charlist(value)
    calculate_base91_value([v1, v2, v3, v4])
  end

  @doc """
  Decodes a compressed cs pair that has no compression type byte to go with it.
  """
  @spec convert_compressed_cs(binary()) :: map()
  def convert_compressed_cs(cs), do: convert_compressed_cs(cs, " ")

  @doc """
  Decodes a compressed cs pair.

  GGA-originated positions use the pair for altitude in feet. Other positions use it for course
  and speed in knots, except for the radio-range marker.
  """
  @spec convert_compressed_cs(binary(), binary()) :: %{
          optional(:course) => pos_integer(),
          optional(:speed) => float(),
          optional(:range) => float(),
          optional(:altitude) => float()
        }
  def convert_compressed_cs(<<c, s>>, compression_type)
      when is_binary(compression_type) and is_base91(c) and is_base91(s) do
    gga? = gga_compression_type?(compression_type)
    c_value = c - 33
    s_value = s - 33

    cond do
      gga? ->
        %{altitude: 1.002 ** (c_value * 91 + s_value)}

      c == ?{ ->
        %{range: 2 * 1.08 ** s_value}

      true ->
        course = if c_value == 0, do: 360, else: c_value * 4
        %{course: course, speed: 1.08 ** s_value - 1}
    end
  end

  def convert_compressed_cs(_, _), do: %{}
end
