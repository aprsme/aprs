defmodule Aprs.AX25 do
  @moduledoc """
  AX.25 callsign and path parsing/validation for APRS packets.
  """

  @doc """
  Parse and validate an AX.25 callsign. Returns {:ok, {base, ssid}} or {:error, reason}.
  """
  @spec parse_callsign(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, String.t()}
  def parse_callsign(callsign) when is_binary(callsign) and byte_size(callsign) > 0 do
    result =
      if String.contains?(callsign, "-") do
        String.split(callsign, "-")
      else
        [callsign]
      end

    format_callsign_result(result, callsign)
  end

  def parse_callsign(callsign) when is_binary(callsign) and byte_size(callsign) == 0 do
    {:error, :invalid_packet}
  end

  def parse_callsign(_) do
    {:error, "Invalid callsign format"}
  end

  defp format_callsign_result([base, ssid], _), do: {:ok, {base, ssid}}
  defp format_callsign_result([base], _), do: {:ok, {base, "0"}}
  defp format_callsign_result(_, original), do: {:ok, {original, "0"}}

  @doc """
  Parse and validate an AX.25 path. Returns {:ok, [String.t()]} or {:error, reason}.
  """
  @spec parse_path(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def parse_path(_path) do
    # Stub: actual logic to be implemented
    {:error, "Not yet implemented"}
  end
end
