defmodule Aprs.Convert do
  @moduledoc """
  Unit conversions used by APRS weather station formats.
  """

  @doc """
  Convert an Ultimeter wind speed (tenths of a kph) to mph.

  ## Examples

      iex> Aprs.Convert.wind(1609, :ultimeter, :mph)
      99.9786247928

  """
  @spec wind(number(), :ultimeter, :mph) :: float()
  def wind(speed, :ultimeter, :mph), do: speed * 0.0621371192

  @doc """
  Convert an Ultimeter temperature (tenths of a degree F) to degrees F.

  ## Examples

      iex> Aprs.Convert.temp(725, :ultimeter, :f)
      72.5

  """
  @spec temp(number(), :ultimeter, :f) :: float()
  def temp(value, :ultimeter, :f), do: value * 0.1
end
