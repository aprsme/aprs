defmodule Aprs.CommentHandlingTest do
  @moduledoc """
  Tests for comment field handling matching FAP.pm behavior.
  """
  use ExUnit.Case, async: true

  describe "PHG stripping" do
    test "PHG followed by digits without slash only strips exactly 4 digits" do
      # KC8YVF - PHG51204 where "4" is part of comment
      packet =
        "KC8YVF>APU25N,TCPIP*,qAC,T2SPAIN:=4326.57NI08401.46W&PHG51204 Ron-Saginaw, MI {UIV32N}"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "4 Ron-Saginaw, MI {UIV32N}"
      assert parsed.data_extended.phg == "5120"
    end

    test "PHG followed by digits and slash strips all digits through slash" do
      # N5UA - PHG51080/ where "0/" is consumed
      packet =
        "N5UA-R>APRS,TCPIP*,qAC,T2SYDNEY:=3259.02N/09642.82WrPHG51080/444.675+ PL 110.9 Connected to 29.66FM"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "444.675+ PL 110.9 Connected to 29.66FM"
      assert parsed.data_extended.phg == "5108"
    end

    test "PHG does not consume digits that are part of comment" do
      # K8JTT - PHG7140 followed by "147.350MHz"
      packet =
        "K8JTT>APDW18,WIDE1-1,WIDE2-1,qAO,N8YAJ-2:!4207.65NS08315.58W#PHG7140147.350MHz Jim-Brownstown-FTM-400XDR.Digirig.RPi4"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "147.350MHz Jim-Brownstown-FTM-400XDR.Digirig.RPi4"
      assert parsed.data_extended.phg == "7140"
    end
  end

  describe "RNG kept in comment" do
    test "RNG text is preserved in comment like FAP" do
      # DB0DY-B - RNG0016 should stay in comment
      packet =
        "DB0DY-B>APDG02,TCPIP*,qAC,DB0DY-BS:!5210.07ND00754.23E&/A=000033RNG0016 440 Voice 439.81250MHz -9.4000MHz"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "RNG0016 440 Voice 439.81250MHz -9.4000MHz"
    end
  end

  describe "DAO extension stripping" do
    test "strips !Wxx! DAO with digits" do
      # DG1ABE - !W02! should be stripped
      packet =
        "DG1ABE-9>APOTC1,WIDE1-1,WIDE2-2,qAR,DB0OHA-10:/182145z5138.32N\\00946.36EP155/000!W02!/A=001192 14.5V 21C Parken  http://www.dg1abe.de"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "14.5V 21C Parken  http://www.dg1abe.de"
    end
  end

  describe "!w..! weather extension stripping" do
    test "strips !wm(! from position comment" do
      # K5LEB - !wm(! weather extension
      packet =
        "K5LEB-7>APFII0,TCPIP*,qAC,APRSFI:@214541h3315.80N/09706.74Wk272/025APMAIL WINLINK!wm(!"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "APMAIL WINLINK"
    end

    test "strips !w%t! from position comment" do
      # PE0FK - !w%t! weather extension
      packet =
        "PE0FK-10>APWW11,TCPIP*,qAC,T2SYDNEY:@214524h5120.50NW00553.58EaPE0FK-10 Winlink RMS Relay-Hold Digipeater, Regio 23, Loc: Meijel,PL:255,MF:4,MS:3, @144.850MHz!w%t!E3."

      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_extended.comment ==
               "PE0FK-10 Winlink RMS Relay-Hold Digipeater, Regio 23, Loc: Meijel,PL:255,MF:4,MS:3, @144.850MHzE3."
    end
  end

  describe "null byte stripping" do
    test "strips trailing null bytes from comment" do
      packet =
        "BM4AIK-4>AIK4BM,WIDE1-1,WIDE2-2,qAS,BM7BGU-4:!2238.19N/12018.14E#Arduino Uno Digipeater {CH340G} " <>
          <<0>>

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "Arduino Uno Digipeater {CH340G}"
    end
  end

  describe "altitude /a= handling" do
    test "preserves a=NNNNNN in comment after extracting altitude" do
      # 9M8J - /a=001462 should leave a=001462 in comment
      packet =
        "9M8J-DX>APRS,TCPIP*,qAC,FIFTH:=0131.19N/11021.58E%/a=001462 https://qsl.marhazk.com/"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "a=001462 https://qsl.marhazk.com/"
      assert parsed.data_extended.altitude == 1462
    end

    test "weather packet preserves /A= in comment" do
      # DG2GGP - weather packet should keep /A= in comment
      packet =
        "DG2GGP-11>APRS,TCPIP*,qAS,dg2ggp:@182145z4806.37N/00828.34E_233/000g000t033r000p023P011h94b10029L000F....V030/A=02260FHEM-WX_aprs-ws_1.8.1"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "F....V030/A=02260FHEM-WX_aprs-ws_1.8.1"
    end
  end

  describe "compressed position telemetry stripping" do
    test "strips |..| telemetry from compressed position comment" do
      # 9W4GWK - telemetry |%(%E| in compressed position
      packet =
        "9W4GWK-G>APLRG1,TCPIP*,qAC,DMRNET01:!LLz(zh/{g_  G.../...g...t088h68b10119Gas: 32.79Kohms iGate HWSL + BME680|%(%E|"

      {:ok, parsed} = Aprs.parse(packet)
      assert parsed.data_extended.comment == "Gas: 32.79Kohms iGate HWSL + BME680|%(%E|"
    end
  end
end
