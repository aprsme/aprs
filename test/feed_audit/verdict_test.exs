defmodule Aprs.FeedAudit.VerdictTest do
  use ExUnit.Case, async: true

  alias Aprs.FeedAudit.Verdict

  doctest Verdict

  describe "classify/2 in :all mode" do
    test "passes a packet whose payload parsed" do
      assert Verdict.classify(Aprs.parse("N0CALL-9>APRS,TCPIP*:!4903.50N/07201.75W>Test"), :all) == :ok
    end

    test "reports a hard parse error" do
      assert Verdict.classify({:error, :invalid_packet}, :all) == {:failure, :invalid_packet}
    end

    test "reports an error message left in data_extended" do
      result = Aprs.parse("N0CALL>APRS:@nonsense")

      assert {:ok, %{data_extended: %{error: "Invalid timestamped position format"}}} = result

      assert Verdict.classify(result, :all) ==
               {:failure, {:payload_error, "Invalid timestamped position format"}}
    end

    test "reports an Aprs.Types.ParseError struct in data_extended" do
      packet = %{data_type: :nmea, data_extended: %{error_code: :not_implemented, error_message: "NMEA stub"}}

      assert Verdict.classify({:ok, packet}, :all) ==
               {:failure, {:payload_error, "not_implemented: NMEA stub"}}
    end

    test "reports a packet with no parsed payload" do
      result = Aprs.parse("N0CALL>APRS:\u007Funknown data type")

      assert {:ok, %{data_extended: nil, data_type: :unknown_datatype}} = result
      assert Verdict.classify(result, :all) == {:failure, {:unparsed_payload, :unknown_datatype}}
    end
  end

  describe "classify/2 in :hard mode" do
    test "ignores payload failures" do
      assert Verdict.classify(Aprs.parse("N0CALL>APRS:@nonsense"), :hard) == :ok
      assert Verdict.classify(Aprs.parse("N0CALL>APRS:\u007Funknown data type"), :hard) == :ok
    end

    test "still reports hard parse errors" do
      assert Verdict.classify({:error, "Parse exception"}, :hard) == {:failure, "Parse exception"}
    end
  end
end
