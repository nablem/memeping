defmodule MemePing.Telegram.RateLimiterTest do
  use ExUnit.Case, async: true

  alias MemePing.Telegram.RateLimiter

  test "spaces concurrent requests by the configured interval" do
    limiter = start_supervised!({RateLimiter, name: :telegram_rate_limiter_test, interval_ms: 50})
    test_pid = self()

    1..2
    |> Task.async_stream(
      fn _ ->
        RateLimiter.execute(limiter, fn -> send(test_pid, {:request_started, timestamp()}) end)
      end,
      ordered: false
    )
    |> Stream.run()

    assert_receive {:request_started, first_started_at}
    assert_receive {:request_started, second_started_at}

    assert abs(second_started_at - first_started_at) >= 45

    assert %{request_count: 2, peak_queue_depth: queue_depth, max_wait_ms: wait_ms} =
             RateLimiter.stats(limiter)

    assert queue_depth >= 0
    assert wait_ms >= 45
  end

  defp timestamp, do: System.monotonic_time(:millisecond)
end
