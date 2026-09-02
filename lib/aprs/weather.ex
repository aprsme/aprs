defmodule Aprs.Weather do
  @moduledoc """
  APRS weather report parsing.
  """

  alias Aprs.WeatherHelpers

  @doc """
  Parse a positionless APRS weather report (the `_` data type).

  Returns the weather fields with `data_type: :weather`. Fields the report
  omits are `nil`.
  """
  @spec parse(String.t()) :: map()
  def parse(data) do
    data
    |> parse_weather_data()
    |> Map.put(:data_type, :weather)
  end

  @doc """
  Parses weather fields into a flat map.
  """
  @spec parse_weather_data(String.t()) :: map()
  def parse_weather_data(weather_data) do
    {weather, _remainder} = parse_weather_data_with_remainder(weather_data)
    weather
  end

  @doc """
  Parses weather fields and returns the trimmed, unconsumed comment bytes.
  """
  @spec parse_weather_data_with_remainder(String.t()) :: {map(), String.t()}
  def parse_weather_data_with_remainder(weather_data) do
    {timestamp, raw_weather_data} = WeatherHelpers.extract_timestamp_and_data(weather_data)
    {weather, remainder} = WeatherHelpers.scan_weather_data(raw_weather_data)

    weather =
      weather
      |> Map.put(:timestamp, timestamp)
      |> Map.put(:raw_weather_data, raw_weather_data)

    {weather, String.trim(remainder)}
  end
end
