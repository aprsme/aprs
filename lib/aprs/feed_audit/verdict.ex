defmodule Aprs.FeedAudit.Verdict do
  @moduledoc """
  Decides whether an `Aprs.parse/1` result counts as a parse failure.

  APRS-IS servers validate framing before relaying, so `Aprs.parse/1` almost
  never returns `{:error, _}` on a live feed. It does however return `{:ok,
  packet}` while the payload parser gave up, recording that inside
  `data_extended`:

    * `data_extended[:error]` - a message such as `"Invalid position format"`
    * `data_extended[:error_code]` / `[:error_message]` - a structured error
    * `data_extended == nil` - no payload was parsed at all, e.g. an
      unrecognised data type identifier

  Those are parse failures, so `classify/2` reports them in `:all` mode (the
  default for the mix tasks). `:hard` reports only `{:error, _}` returns.
  """

  @typedoc "Which failures to report."
  @type mode :: :all | :hard

  @doc """
  Classifies a parse result; `{:failure, reason}` means it should be reported.

  ## Examples

      iex> Aprs.FeedAudit.Verdict.classify({:error, :invalid_packet}, :all)
      {:failure, :invalid_packet}

      iex> Aprs.FeedAudit.Verdict.classify(Aprs.parse("N0CALL>APRS:@nonsense"), :all)
      {:failure, {:payload_error, "Invalid timestamped position format"}}

      iex> Aprs.FeedAudit.Verdict.classify(Aprs.parse("N0CALL>APRS:@nonsense"), :hard)
      :ok

  """
  @spec classify(term(), mode()) :: :ok | {:failure, term()}
  def classify({:error, reason}, _mode), do: {:failure, reason}
  def classify({:ok, _packet}, :hard), do: :ok
  def classify({:ok, packet}, :all), do: payload_verdict(packet)

  defp payload_verdict(%{data_extended: %{error_code: code} = extended}) when not is_nil(code) do
    {:failure, {:payload_error, "#{code}: #{Map.get(extended, :error_message)}"}}
  end

  defp payload_verdict(%{data_extended: %{error: error}}) when not is_nil(error) do
    {:failure, {:payload_error, to_string(error)}}
  end

  defp payload_verdict(%{data_extended: nil, data_type: data_type}) do
    {:failure, {:unparsed_payload, data_type}}
  end

  defp payload_verdict(_packet), do: :ok
end
