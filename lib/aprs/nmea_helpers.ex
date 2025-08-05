defmodule Aprs.NMEAHelpers do
  @moduledoc """
  NMEA coordinate and sentence parsing helpers for APRS.
  """

  @spec parse_nmea_coordinate(String.t(), String.t()) :: {:ok, float()} | {:error, String.t()}
  def parse_nmea_coordinate(value, direction) when is_binary(value) and is_binary(direction) do
    case Float.parse(value) do
      {coord, _} ->
        normalized = coord / 100.0
        result = apply_nmea_direction(normalized, direction)
        handle_coordinate_result(result)

      _ ->
        {:error, "Invalid coordinate value"}
    end
  end

  @spec parse_nmea_coordinate(any(), any()) :: {:error, String.t()}
  def parse_nmea_coordinate(_, _), do: {:error, "Invalid coordinate format"}

  defp handle_coordinate_result(coord) when is_tuple(coord), do: coord
  defp handle_coordinate_result(coord), do: {:ok, coord}

  defp apply_nmea_direction(coord, "N"), do: coord
  defp apply_nmea_direction(coord, "S"), do: -coord
  defp apply_nmea_direction(coord, "E"), do: coord
  defp apply_nmea_direction(coord, "W"), do: -coord
  defp apply_nmea_direction(_, _), do: {:error, "Invalid coordinate direction"}

  @spec parse_nmea_sentence(any()) :: {:error, String.t()}
  def parse_nmea_sentence(_sentence) do
    {:error, "NMEA parsing not implemented"}
  end
end
