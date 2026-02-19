defmodule Aprs.Parser.PositionFrequencyTest do
  use ExUnit.Case, async: true

  describe "frequency data in position comments" do
    test "frequency info like '444.975MHz' should not be parsed as course/speed" do
      packet = "N0CALL>APRS:=3903.50N/07201.75W>444.975MHz Repeater"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "444.975MHz Repeater"
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end

    test "pattern '444/100' is consumed with invalid course set to 0 (FAP behavior)" do
      # FAP behavior: matches and strips NNN/NNN, sets invalid course (>360) to 0
      packet = "N0CALL>APRS:=3903.50N/07201.75W>444/100 Testing"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "Testing"
      assert parsed.data_extended[:course] == 0
      assert parsed.data_extended[:speed] == 100.0
    end

    test "course/speed pattern with leading '/' is not consumed" do
      # FAP behavior: leading '/' prevents course/speed match, gets stripped as delimiter
      packet = "N0CALL>APRS:=3903.50N/07201.75W>/090/045 Moving East at 45kt"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "090/045 Moving East at 45kt"
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end

    test "frequency with tone '444.975/100.0' is not parsed as course/speed" do
      # Pattern doesn't match at start of comment (starts with "On")
      packet = "N0CALL>APRS:=3903.50N/07201.75W>On 444.975/100.0 tone"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "On 444.975/100.0 tone"
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end

    test "course values >360 set course to 0 (FAP behavior)" do
      # FAP behavior: invalid course (> 360) sets course to 0, still consumed
      packet = "N0CALL>APRS:=3903.50N/07201.75W>999/100"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:course] == 0
      assert parsed.data_extended[:speed] == 100.0
    end

    test "position packets without course/speed pattern" do
      packet = "N0CALL>APRS:=3903.50N/07201.75W>Just a normal comment"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "Just a normal comment"
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end

    test "timestamped position with frequency info" do
      # Test with timestamped position format (@)
      packet = "N0CALL>APRS:@123456z3903.50N/07201.75W>444.975MHz Repeater"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :timestamped_position_with_message
      assert parsed.data_extended[:comment] == "444.975MHz Repeater"
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end

    test "regular position (!) with frequency pattern consumed (FAP behavior)" do
      # FAP behavior: 444/100 matches NNN/NNN, course 444>360 set to 0
      packet = "N0CALL>APRS:!3903.50N/07201.75W>444/100 Test"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position
      assert parsed.data_extended[:comment] == "Test"
      assert parsed.data_extended[:course] == 0
      assert parsed.data_extended[:speed] == 100.0
    end

    test "PHG data followed by frequency is not parsed as course/speed - user reported case" do
      # This is the actual packet reported by the user - now correctly handled
      packet =
        "N5UA-R>APRS,TCPIP*,qAC,T2SYDNEY:=3259.02N/09642.82WrPHG51080/444.675+ PL 110.9 Connected to 29.66FM"

      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      # PHG is extracted and stripped from comment (FAP-compatible behavior)
      assert parsed.data_extended[:comment] == "444.675+ PL 110.9 Connected to 29.66FM"
      assert parsed.data_extended[:phg] == "5108"
      # Fixed behavior - PHG data is skipped
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end
  end
end
