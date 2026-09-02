defmodule Aprs.FeedAudit.Failure do
  @moduledoc """
  One record describing a packet that failed to parse: the packet and why.

  Used by `mix aprs.parse_feed` and `mix aprs.parse_file`, which write one
  record per line as JSON, so the output reads as plain text and parses with
  `jq`. Raw bytes are byte-escaped (`\\xNN`) because APRS frames are frequently
  not valid UTF-8.

  JSON is rendered by `to_json/1` rather than an encoder library: this library
  has no runtime dependencies and the records are four flat fields.
  """

  @typedoc "A single parse failure."
  @type t :: %{
          seq: pos_integer(),
          received_at: String.t(),
          error: String.t(),
          raw: String.t()
        }

  @doc """
  Builds a failure record for `raw` given the parser's `reason`.

  Options:

    * `:seq` - 1-based failure sequence number within a run (default `1`)
    * `:received_at` - `DateTime` the frame was read (default `DateTime.utc_now/0`)

  ## Examples

      iex> failure = Aprs.FeedAudit.Failure.build("bogus line", :invalid_packet, seq: 3)
      iex> {failure.seq, failure.error, failure.raw}
      {3, "invalid_packet", "bogus line"}

  """
  @spec build(binary(), term(), keyword()) :: t()
  def build(raw, reason, opts \\ []) when is_binary(raw) do
    received_at = Keyword.get(opts, :received_at) || DateTime.utc_now()

    %{
      seq: Keyword.get(opts, :seq, 1),
      received_at: received_at |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601(),
      error: format_reason(reason),
      raw: escape(raw)
    }
  end

  @doc """
  Renders a failure record as a single-line JSON object.

  ## Examples

      iex> "bad" |> Aprs.FeedAudit.Failure.build(:invalid_packet, received_at: ~U[2026-01-01 00:00:00Z]) |> Aprs.FeedAudit.Failure.to_json()
      ~s({"seq":1,"received_at":"2026-01-01T00:00:00Z","error":"invalid_packet","raw":"bad"})

  """
  @spec to_json(t()) :: String.t()
  def to_json(failure) do
    IO.iodata_to_binary([
      ~s({"seq":),
      Integer.to_string(failure.seq),
      ~s(,"received_at":),
      json_string(failure.received_at),
      ~s(,"error":),
      json_string(failure.error),
      ~s(,"raw":),
      json_string(failure.raw),
      "}"
    ])
  end

  @doc """
  Escapes a raw frame into a printable string.

  Valid UTF-8 codepoints outside the control range pass through untouched;
  control bytes, `DEL`, and bytes that are not valid UTF-8 become `\\xNN`, and a
  literal backslash is doubled so the escaping stays unambiguous.

  ## Examples

      iex> Aprs.FeedAudit.Failure.escape(<<"a", 0xFF, "b\\\\">>)
      "a\\\\xFFb\\\\\\\\"

  """
  @spec escape(binary()) :: String.t()
  def escape(raw) when is_binary(raw) do
    raw |> do_escape([]) |> IO.iodata_to_binary()
  end

  defp do_escape(<<>>, acc), do: Enum.reverse(acc)
  defp do_escape(<<?\\, rest::binary>>, acc), do: do_escape(rest, ["\\\\" | acc])

  defp do_escape(<<codepoint::utf8, rest::binary>>, acc) when codepoint >= 0x20 and codepoint != 0x7F do
    do_escape(rest, [<<codepoint::utf8>> | acc])
  end

  defp do_escape(<<byte, rest::binary>>, acc) do
    do_escape(rest, ["\\x" <> Base.encode16(<<byte>>) | acc])
  end

  # `{:payload_error, _}` and `{:unparsed_payload, _}` come from
  # `Aprs.FeedAudit.Verdict`: the frame parsed, but its payload did not.
  defp format_reason({:payload_error, message}), do: "payload: #{message}"
  defp format_reason({:unparsed_payload, data_type}), do: "unparsed payload (#{data_type})"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp json_string(value) do
    [?", value |> do_json_escape([]) |> Enum.reverse(), ?"]
  end

  defp do_json_escape(<<>>, acc), do: acc
  defp do_json_escape(<<?", rest::binary>>, acc), do: do_json_escape(rest, ["\\\"" | acc])
  defp do_json_escape(<<?\\, rest::binary>>, acc), do: do_json_escape(rest, ["\\\\" | acc])

  defp do_json_escape(<<byte, rest::binary>>, acc) when byte < 0x20 do
    do_json_escape(rest, ["\\u00" <> Base.encode16(<<byte>>) | acc])
  end

  defp do_json_escape(<<byte, rest::binary>>, acc), do: do_json_escape(rest, [<<byte>> | acc])
end
