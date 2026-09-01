defmodule Aprs.TelemetryHelpers do
  @moduledoc """
  Telemetry helpers for APRS.
  """

  @spec parse_coefficient(String.t()) :: float() | String.t()
  def parse_coefficient(coefficient) do
    case Float.parse(coefficient) do
      {number, _remainder} -> number
      :error -> coefficient
    end
  end
end
