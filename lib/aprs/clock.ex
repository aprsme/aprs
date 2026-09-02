defmodule Aprs.Clock do
  @moduledoc """
  Wall clock reads for the parser.

  Every parsed packet is stamped with `received_at`, and every packet carrying
  an APRS timestamp needs the current time to resolve a day-hour-minute field
  against, so reading the clock is on the hot path. Most of the cost of
  `DateTime.utc_now/1` is turning a unix second into a calendar date, and that
  answer only changes once a second, so it is cached per process and only the
  microsecond field is refreshed.
  """

  @cache_key {__MODULE__, :second}

  @doc """
  The current UTC time, to microsecond precision.

  Equivalent to `DateTime.utc_now(:microsecond)`.
  """
  @spec utc_now() :: DateTime.t()
  def utc_now do
    microseconds = :os.system_time(:microsecond)
    second = div(microseconds, 1_000_000)

    %{second_datetime(second) | microsecond: {rem(microseconds, 1_000_000), 6}}
  end

  @spec second_datetime(integer()) :: DateTime.t()
  defp second_datetime(second) do
    case :erlang.get(@cache_key) do
      {^second, datetime} -> datetime
      _stale_or_missing -> cache_second(second)
    end
  end

  @spec cache_second(integer()) :: DateTime.t()
  defp cache_second(second) do
    datetime = DateTime.from_unix!(second)
    :erlang.put(@cache_key, {second, datetime})
    datetime
  end
end
