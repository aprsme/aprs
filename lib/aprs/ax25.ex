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
    split_ssid(callsign, :binary.split(callsign, "-"))
  end

  def parse_callsign(_), do: {:error, "Invalid callsign format"}

  # A single hyphen separates the base callsign from the SSID; a callsign with
  # more than one hyphen is not an AX.25 address, so it is kept verbatim.
  @spec split_ssid(String.t(), [String.t()]) :: {:ok, {String.t(), String.t()}}
  defp split_ssid(callsign, [base, ssid]) when byte_size(ssid) > 0 do
    case :binary.match(ssid, "-") do
      :nomatch -> {:ok, {base, ssid}}
      _match -> {:ok, {callsign, "0"}}
    end
  end

  defp split_ssid(_callsign, [base, ssid]), do: {:ok, {base, ssid}}
  defp split_ssid(_callsign, [base]), do: {:ok, {base, "0"}}
end
