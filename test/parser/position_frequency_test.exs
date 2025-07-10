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

    test "pattern '444/100' is correctly rejected due to invalid course (>360)" do
      # Course values > 360 are invalid and should not be parsed
      packet = "N0CALL>APRS:=3903.50N/07201.75W>444/100 Testing"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "444/100 Testing"
      # Fixed behavior - course > 360 is rejected
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end

    test "legitimate course/speed pattern '/090/045' is correctly parsed" do
      packet = "N0CALL>APRS:=3903.50N/07201.75W>/090/045 Moving East at 45kt"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "/090/045 Moving East at 45kt"
      assert parsed.data_extended[:course] == 90
      assert parsed.data_extended[:speed] == 45.0
    end

    test "frequency with tone '444.975/100.0' is not parsed as course/speed" do
      # Pattern doesn't match at start of comment (starts with "On")
      packet = "N0CALL>APRS:=3903.50N/07201.75W>On 444.975/100.0 tone"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "On 444.975/100.0 tone"
      # Fixed behavior - pattern must be at start of comment
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end

    test "course values must be constrained to 0-360 degrees" do
      # Invalid course values (> 360) are now rejected
      packet = "N0CALL>APRS:=3903.50N/07201.75W>999/100"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      # Fixed behavior - rejects invalid course value
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
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

    test "regular position (!) with frequency pattern" do
      # Test with regular position format (!)
      packet = "N0CALL>APRS:!3903.50N/07201.75W>444/100 Test"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position
      assert parsed.data_extended[:comment] == "444/100 Test"
      # Fixed behavior - rejects invalid course
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end

    test "PHG data followed by frequency is not parsed as course/speed - user reported case" do
      # This is the actual packet reported by the user - now correctly handled
      packet = "N5UA-R>APRS,TCPIP*,qAC,T2SYDNEY:=3259.02N/09642.82WrPHG51080/444.675+ PL 110.9 Connected to 29.66FM"
      {:ok, parsed} = Aprs.parse(packet)

      assert parsed.data_type == :position_with_message
      assert parsed.data_extended[:comment] == "PHG51080/444.675+ PL 110.9 Connected to 29.66FM"
      # Fixed behavior - PHG data is skipped
      assert parsed.data_extended[:course] == nil
      assert parsed.data_extended[:speed] == nil
    end
  end
end
