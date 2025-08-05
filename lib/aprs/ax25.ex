defmodule Aprs.AX25 do
  @moduledoc """
  AX.25 callsign and path parsing/validation for APRS packets.
  """

  @doc """
  Parse and validate an AX.25 callsign. Returns {:ok, {base, ssid}} or {:error, reason}.
  """
  @spec parse_callsign(String.t()) :: {:ok, {String.t(), String.t()}} | {:error, String.t()}
  def parse_callsign(callsign) when is_binary(callsign) and byte_size(callsign) > 0 do
    if String.contains?(callsign, "-") do
      case String.split(callsign, "-") do
        [base, ssid] -> {:ok, {base, ssid}}
        _ -> {:ok, {callsign, "0"}}
      end
    else
      {:ok, {callsign, "0"}}
    end
  end

  def parse_callsign(callsign) when is_binary(callsign) and byte_size(callsign) == 0 do
    {:error, :invalid_packet}
  end

  def parse_callsign(_) do
    {:error, "Invalid callsign format"}
  end

  @doc """
  Parse and validate an AX.25 path. Returns {:ok, [String.t()]} or {:error, reason}.
  """
  @spec parse_path(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def parse_path(_path) do
    # Stub: actual logic to be implemented
    {:error, "Not yet implemented"}
  end
end
