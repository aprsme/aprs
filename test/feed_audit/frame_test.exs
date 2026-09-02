defmodule Aprs.FeedAudit.FrameTest do
  use ExUnit.Case, async: true

  alias Aprs.FeedAudit.Frame

  doctest Frame

  describe "strip_eol/1" do
    test "strips CRLF, LF and CR" do
      assert Frame.strip_eol("line\r\n") == "line"
      assert Frame.strip_eol("line\n") == "line"
      assert Frame.strip_eol("line\r") == "line"
    end

    test "strips one line ending only" do
      assert Frame.strip_eol("line\n\n") == "line\n"
      assert Frame.strip_eol("line\r\r") == "line\r"
    end

    test "leaves a line without a line ending alone" do
      assert Frame.strip_eol("line") == "line"
      assert Frame.strip_eol("") == ""
    end

    test "works on bytes that are not valid UTF-8" do
      assert Frame.strip_eol(<<0xFF, 0xFE, "\r\n">>) == <<0xFF, 0xFE>>
      assert Frame.strip_eol(<<0x80>>) == <<0x80>>
    end
  end
end
