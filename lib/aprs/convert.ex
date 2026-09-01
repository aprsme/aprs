defmodule Aprs.Convert do
  @moduledoc """
  Unit conversions used by APRS weather station formats.
  """

  @spec wind(number(), :ultimeter, :mph) :: float()
  def wind(speed, :ultimeter, :mph), do: speed * 0.0621371192

  @spec temp(number(), :ultimeter, :f) :: float()
  def temp(value, :ultimeter, :f), do: value * 0.1
end
