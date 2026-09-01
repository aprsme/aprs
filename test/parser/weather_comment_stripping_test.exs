defmodule Aprs.WeatherCommentStrippingTest do
  use ExUnit.Case, async: true

  alias Aprs.Weather

  describe "parse_weather_data_with_remainder/1" do
    test "preserves a dot separator before a software identifier" do
      {_weather, remainder} =
        Weather.parse_weather_data_with_remainder("000/000g001t042r000p001P000h78b10049L339.DsWLL")

      assert remainder == ".DsWLL"
    end

    test "preserves weather-looking bytes after the comment starts" do
      {_weather, remainder} =
        Weather.parse_weather_data_with_remainder("000/000g000t010r000p000P000h80b10166ESP8266-BME280")

      assert remainder == "ESP8266-BME280"
    end

    test "consumes a five-digit pressure and three-digit temperature" do
      {weather, remainder} =
        Weather.parse_weather_data_with_remainder("082/002g006t033r000p057P050h00b09959L027 Station")

      assert weather.temperature == 33
      assert weather.pressure == 995.9
      assert remainder == "Station"
    end

    test "leaves non-spec short fields in the remainder" do
      {_weather, remainder} = Weather.parse_weather_data_with_remainder("000/000g000t73b9959L027")

      assert remainder == "t73b9959L027"
    end
  end

  describe "position weather comments through Aprs.parse/1" do
    test "preserves dot before software identifier" do
      packet =
        "K7LER>APRS,TCPIP*,qAC,FIFTH:@182145z4733.51N/12223.25W_000/000g001t042r000p001P000h78b10049L339.DsWLL"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == ".DsWLL"
    end

    test "preserves a comment containing a rain-like token" do
      packet =
        "R1CBW-13>APRS,TCPIP*,qAC,T2PERTH:!5957.16N/03034.48E_000/000g000t010r000p000P000h80b10166ESP8266-BME280"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "ESP8266-BME280"
    end

    test "does not strip weather-like text from a non-weather position comment" do
      packet =
        "DW8BRQ-10>APSTAR,TCPIP*,qAC,T2FINLAND:!0829.81N/12435.65E-" <>
          "PHG1210/A=000033DW8BRQ Node ASL52453 http://52453.example/"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "DW8BRQ Node ASL52453 http://52453.example/"
    end
  end
end
