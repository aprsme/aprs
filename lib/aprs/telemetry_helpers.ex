defmodule Aprs.TelemetryHelpers do
  @moduledoc """
  Telemetry helpers for APRS.
  """

  @doc """
  Parse one `EQNS.` coefficient, returning the string unchanged when it is not
  a number.

  ## Examples

      iex> Aprs.TelemetryHelpers.parse_coefficient("1.5")
      1.5

      iex> Aprs.TelemetryHelpers.parse_coefficient("abc")
      "abc"

  """
  @spec parse_coefficient(String.t()) :: float() | String.t()
  def parse_coefficient(coefficient) do
    case Float.parse(coefficient) do
      {number, _remainder} -> number
      :error -> coefficient
    end
  end
end
