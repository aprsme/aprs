defmodule Aprs.ClockTest do
  use ExUnit.Case, async: true

  alias Aprs.Clock

  describe "utc_now/0" do
    test "returns a UTC datetime with microsecond precision" do
      datetime = Clock.utc_now()

      assert %DateTime{time_zone: "Etc/UTC", utc_offset: 0, std_offset: 0} = datetime
      assert {microsecond, 6} = datetime.microsecond
      assert microsecond in 0..999_999
    end

    test "agrees with DateTime.utc_now/1" do
      before = DateTime.utc_now(:microsecond)
      datetime = Clock.utc_now()
      later = DateTime.utc_now(:microsecond)

      assert DateTime.compare(datetime, before) in [:gt, :eq]
      assert DateTime.compare(datetime, later) in [:lt, :eq]
    end

    test "keeps the calendar fields correct once the cached second is stale" do
      first = Clock.utc_now()
      Process.sleep(1_100)
      second = Clock.utc_now()

      assert DateTime.after?(second, first)
      assert second == DateTime.from_unix!(DateTime.to_unix(second, :microsecond), :microsecond)
    end

    test "reads the clock independently in each process" do
      task = Task.async(&Clock.utc_now/0)

      assert %DateTime{} = Task.await(task)
      assert %DateTime{} = Clock.utc_now()
    end
  end
end
