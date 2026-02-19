defmodule Aprs.WeatherCommentStrippingTest do
  @moduledoc """
  Tests for weather comment stripping matching FAP.pm behavior.
  Weather fields should only be consumed from the front of the comment,
  not globally replaced throughout the string.
  """
  use ExUnit.Case, async: true

  describe "weather comment preserves leading dot" do
    test "preserves dot separator before software identifier" do
      # K7LER packet - weather followed by .DsWLL
      packet =
        "K7LER>APRS,TCPIP*,qAC,FIFTH:@182145z4733.51N/12223.25W_000/000g001t042r000p001P000h78b10049L339.DsWLL"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == ".DsWLL"
    end

    test "preserves dot before weewx identifier" do
      # DC1NF packet - weather followed by .weewx-4.10.2-FineOffsetUSB
      packet =
        "DC1NF-7>APRS,TCPIP*,qAC,SEVENTH:@182145z4942.00N/01046.14E_065/003g008t033r000p001P001b10063h81.weewx-4.10.2-FineOffsetUSB"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == ".weewx-4.10.2-FineOffsetUSB"
    end
  end

  describe "weather barometric 4-digit support" do
    test "strips 4-digit barometric pressure" do
      # WD9U packet - b9959 is only 4 digits
      packet =
        "WD9U>APU25N,TCPIP*,qAC,T2MCI:@182145z4634.97N/09052.76W_082/002g006t033r000p057P050h00b9959L027"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == ""
    end

    test "strips 4-digit barometric and handles humidity with dots" do
      # EA3AGQ packet - b8220, h.., v-02
      packet =
        "EA3AGQ-1>APEWX,ED3YAW-15,ED3YAB-15*,WIDE4-2,qAR,EA3ICF-1:@130936z4202.38N/00047.23E_356/000g000t...r000b8220h..v-02 Prv.Pluja"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "Prv.Pluja"
    end
  end

  describe "weather stripping does not corrupt comment text" do
    test "does not strip weather-like patterns from inside comment" do
      # DW8BRQ packet - comment has "ASL52453" which should NOT have L524 stripped
      packet =
        "DW8BRQ-10>APSTAR,TCPIP*,qAC,T2FINLAND:!0829.81N/12435.65E-PHG1210/A=000033DW8BRQ Dodoy Harmonic Maicah and Lemo QTH  Silang St. Iponan Cagayan de Oro City- AllstarLnk3 Node 483876 Link to Node ASL52453  http://52453.ip.hamvoip.org/allmon3/"

      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_extended.comment ==
               "DW8BRQ Dodoy Harmonic Maicah and Lemo QTH  Silang St. Iponan Cagayan de Oro City- AllstarLnk3 Node 483876 Link to Node ASL52453  http://52453.ip.hamvoip.org/allmon3/"
    end

    test "does not strip P from ESP8266" do
      # R1CBW packet - comment has "ESP8266-BME280" which should NOT have P826 stripped
      packet =
        "R1CBW-13>APRS,TCPIP*,qAC,T2PERTH:!5957.16N/03034.48E_000/000g000t010r000p000P000h80b10166ESP8266-BME280"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "ESP8266-BME280"
    end
  end

  describe "weather temperature 2-digit support" do
    test "strips 2-digit temperature" do
      # VU2LWM packet - t73 is only 2 digits
      packet =
        "VU2LWM-5>APRMCU,TCPIP*,qAC,T2SPAIN:=1744.52N/08319.99E_.../...g...t73r...p...P...h100b10103APRS on VU2LWM WX Station"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "APRS on VU2LWM WX Station"
    end
  end
end
