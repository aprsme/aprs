defmodule Aprs.FeedAudit.Frame do
  @moduledoc """
  Frame handling shared by `mix aprs.parse_feed` and `mix aprs.parse_file`.

  A frame that fails to parse is not necessarily valid UTF-8, so line endings
  are stripped by matching bytes rather than with the `String` functions, which
  assume a valid encoding.
  """

  @doc """
  Strips one trailing line feed, then one trailing carriage return.

  ## Examples

      iex> Aprs.FeedAudit.Frame.strip_eol("N0CALL>APRS:>hi\\r\\n")
      "N0CALL>APRS:>hi"

      iex> Aprs.FeedAudit.Frame.strip_eol(<<0xFF, "\\n">>)
      <<0xFF>>

  """
  @spec strip_eol(binary()) :: binary()
  def strip_eol(line), do: line |> strip_last(?\n) |> strip_last(?\r)

  @spec strip_last(binary(), byte()) :: binary()
  defp strip_last(<<>>, _byte), do: <<>>

  defp strip_last(line, byte) do
    body_size = byte_size(line) - 1

    case line do
      <<body::binary-size(^body_size), ^byte>> -> body
      _other -> line
    end
  end
end
