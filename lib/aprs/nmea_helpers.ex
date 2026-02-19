defmodule Aprs.NMEAHelpers do
  @moduledoc """
  NMEA coordinate and sentence parsing helpers for APRS.
  """

  @spec parse_nmea_coordinate(String.t(), String.t()) :: {:ok, float()} | {:error, String.t()}
  def parse_nmea_coordinate(value, direction) when is_binary(value) and is_binary(direction) do
    case Float.parse(value) do
      {coord, _} ->
        degrees = trunc(coord / 100)
        minutes = coord - degrees * 100
        result = degrees + minutes / 60.0
        normalized = apply_nmea_direction(result, direction)
        handle_coordinate_result(normalized)

      _ ->
        {:error, "Invalid coordinate value"}
    end
  end

  @spec parse_nmea_coordinate(any(), any()) :: {:error, String.t()}
  def parse_nmea_coordinate(_, _), do: {:error, "Invalid coordinate format"}

  @spec handle_coordinate_result({:error, String.t()} | float()) :: {:ok, float()} | {:error, String.t()}
  defp handle_coordinate_result(coord) when is_tuple(coord), do: coord
  defp handle_coordinate_result(coord), do: {:ok, coord}

  @spec apply_nmea_direction(float(), String.t()) :: float() | {:error, String.t()}
  defp apply_nmea_direction(coord, "N"), do: coord
  defp apply_nmea_direction(coord, "S"), do: -coord
  defp apply_nmea_direction(coord, "E"), do: coord
  defp apply_nmea_direction(coord, "W"), do: -coord
  defp apply_nmea_direction(_, _), do: {:error, "Invalid coordinate direction"}

  @spec parse_nmea_sentence(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_nmea_sentence(<<"$GPRMC,", _rest::binary>> = sentence) when is_binary(sentence) do
    fields = String.split(sentence, ",")
    parse_gprmc(fields)
  end

  # Handle case where $ prefix is already stripped by dispatcher
  def parse_nmea_sentence(<<"GPRMC,", _rest::binary>> = sentence) when is_binary(sentence) do
    fields = String.split(sentence, ",")
    parse_gprmc(fields)
  end

  def parse_nmea_sentence(<<"$", _rest::binary>>) do
    {:error, "Unsupported NMEA sentence type"}
  end

  # Handle stripped-prefix non-GPRMC NMEA sentences (e.g. GPGGA from dispatcher)
  def parse_nmea_sentence(<<"GP", _rest::binary>>) do
    {:error, "Unsupported NMEA sentence type"}
  end

  def parse_nmea_sentence(sentence) when is_binary(sentence) and byte_size(sentence) > 0 do
    {:error, "Not an NMEA sentence"}
  end

  def parse_nmea_sentence(_), do: {:error, "Invalid NMEA input"}

  @spec parse_gprmc([String.t()]) ::
          {:ok, %{latitude: float(), longitude: float(), speed: integer(), course: integer(), format: String.t()}}
          | {:error, String.t()}
  defp parse_gprmc([_type, _time, "A", lat, lat_dir, lon, lon_dir, speed_knots, course | _rest]) do
    with {:ok, latitude} <- parse_nmea_coordinate(lat, lat_dir),
         {:ok, longitude} <- parse_nmea_coordinate(lon, lon_dir) do
      speed = parse_int_field(speed_knots)
      course_val = parse_int_field(course)

      {:ok,
       %{
         latitude: latitude,
         longitude: longitude,
         speed: speed,
         course: course_val,
         format: "nmea"
       }}
    end
  end

  defp parse_gprmc([_type, _time, "V" | _rest]) do
    {:error, "GPRMC void status"}
  end

  defp parse_gprmc(_fields) do
    {:error, "Invalid GPRMC sentence"}
  end

  @spec parse_int_field(String.t()) :: integer()
  defp parse_int_field(str) do
    case Float.parse(str) do
      {val, _} -> trunc(val)
      :error -> 0
    end
  end
end
