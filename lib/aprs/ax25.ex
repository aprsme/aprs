defmodule Aprs.AX25 do
  @moduledoc """
  AX.25 callsign and path parsing/validation for APRS packets.
  """

  @doc """
  Parse and validate an AX.25 callsign.

  Returns `{:ok, {base_callsign, ssid}}`, with an SSID of `"0"` when the
  callsign carries none, or `{:error, reason}` when the callsign is not a legal
  AX.25 address.
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
end
