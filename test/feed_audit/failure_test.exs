defmodule Aprs.FeedAudit.FailureTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Aprs.FeedAudit.Failure

  doctest Failure

  describe "build/3" do
    test "records the packet, the reason and the sequence number" do
      raw = "totally bogus line"

      failure = Failure.build(raw, :invalid_packet, seq: 7)

      assert failure.seq == 7
      assert failure.error == "invalid_packet"
      assert failure.raw == raw
      assert failure.received_at =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end

    test "formats binary, payload and unparsed-payload reasons" do
      assert Failure.build("x", "Parse exception").error == "Parse exception"

      assert Failure.build("x", {:payload_error, "Invalid position format"}).error ==
               "payload: Invalid position format"

      assert Failure.build("x", {:unparsed_payload, :unknown_datatype}).error ==
               "unparsed payload (unknown_datatype)"
    end

    test "formats any other reason with inspect" do
      assert Failure.build("x", {:weird, 42}).error == "{:weird, 42}"
      assert Failure.build("x", 42).error == "42"
    end

    test "escapes control bytes, invalid utf8 and backslashes" do
      failure = Failure.build(<<"N0CALL>APRS:!", 0xFF, 0x01, "tail\\">>, :invalid_packet)

      assert failure.raw == "N0CALL>APRS:!\\xFF\\x01tail\\\\"
    end

    test "keeps valid multi-byte utf8 intact" do
      assert Failure.build("N0CALL>APRS:>caf\u00e9", :invalid_packet).raw == "N0CALL>APRS:>caf\u00e9"
    end
  end

  describe "to_json/1" do
    test "renders one line of JSON" do
      json =
        "bogus line"
        |> Failure.build(:invalid_packet, seq: 2, received_at: ~U[2026-01-02 03:04:05.678Z])
        |> Failure.to_json()

      assert json ==
               ~s({"seq":2,"received_at":"2026-01-02T03:04:05.678Z","error":"invalid_packet","raw":"bogus line"})

      refute json =~ "\n"
    end

    test "escapes quotes and backslashes so the line stays valid JSON" do
      json =
        ~s(N0CALL>APRS:>say "hi" \\ bye)
        |> Failure.build({:payload_error, ~s(bad "value")})
        |> Failure.to_json()

      assert json =~ ~s("error":"payload: bad \\"value\\"")
      assert json =~ ~s("raw":"N0CALL>APRS:>say \\"hi\\" \\\\\\\\ bye")
    end

    test "escapes control bytes in the reason so the line stays valid JSON" do
      json =
        "frame"
        |> Failure.build({:payload_error, <<"bad", 0x01, "value">>})
        |> Failure.to_json()

      assert json =~ ~s("error":"payload: bad\\u0001value")
      refute String.contains?(json, <<0x01>>)
    end

    property "a rendered failure is one line with no raw control bytes" do
      check all raw <- StreamData.binary() do
        json = raw |> Failure.build(:invalid_packet) |> Failure.to_json()

        assert String.starts_with?(json, "{")
        assert String.ends_with?(json, "}")
        assert json =~ ~s("raw":")
        refute Enum.any?(:binary.bin_to_list(json), &(&1 < 0x20))
      end
    end
  end
end
