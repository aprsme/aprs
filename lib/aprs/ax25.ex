defmodule Aprs.AX25 do
  @moduledoc """
  AX.25 callsign and path parsing/validation for APRS packets.
  """

  @doc """
  Parse and validate an AX.25 callsign. Returns {:ok, {base, ssid}} or {:error, reason}.
  """
  @spec parse_callsign(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, atom() | String.t()}
  def parse_callsign(""), do: {:error, :invalid_packet}

  def parse_callsign(callsign) when is_binary(callsign) do
    callsign |> String.split("-") |> format_callsign_result(callsign)
  end

  def parse_callsign(_), do: {:error, "Invalid callsign format"}

  @spec format_callsign_result([String.t()], String.t()) :: {:ok, {String.t(), String.t()}}
  defp format_callsign_result([base, ssid], _), do: {:ok, {base, ssid}}
  defp format_callsign_result([base], _), do: {:ok, {base, "0"}}
  defp format_callsign_result(_, original), do: {:ok, {original, "0"}}

  @doc """
  Parse and validate an AX.25 path. Returns {:ok, [String.t()]} or {:error, reason}.
  """
  @spec parse_path(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def parse_path(path) when is_binary(path) do
    segments = String.split(path, ",")

    if Enum.all?(segments, &(&1 != "")) and segments != [] do
      {:ok, segments}
    else
      {:error, "Invalid path"}
    end
  end

  def parse_path(_), do: {:error, "Invalid path"}
end
