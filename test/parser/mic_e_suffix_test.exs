defmodule Aprs.MicESuffixTest do
  use ExUnit.Case, async: true

  alias Aprs.MicE

  @body "`(_fn\"Oj/"

  describe "trailing marker stripping" do
    test "a trailing marker is removed" do
      assert %{comment: "/hello"} = MicE.parse(@body <> "hello --", "T7SXYZ", :mic_e)
    end

    test "a trailing marker in front of a line feed is still removed" do
      assert %{comment: "/hello"} = MicE.parse(@body <> "hello --\n", "T7SXYZ", :mic_e)
    end

    test "a caret marker in front of a line feed is still removed" do
      assert %{comment: "/hello"} = MicE.parse(@body <> "hello^ --\n", "T7SXYZ", :mic_e)
    end

    test "a marker that is not at the end of the comment is kept" do
      assert %{comment: "/hello -- there"} = MicE.parse(@body <> "hello -- there", "T7SXYZ", :mic_e)
    end
  end
end
