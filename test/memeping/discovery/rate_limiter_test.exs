defmodule MemePing.Discovery.RateLimiterTest do
  use ExUnit.Case, async: false

  alias MemePing.Discovery.RateLimiter

  test "records requests and wait time while enforcing the shared interval" do
    RateLimiter.execute(fn -> :ok end)
    RateLimiter.execute(fn -> :ok end)

    assert %{request_count: count, max_wait_ms: wait_ms} = RateLimiter.stats()
    assert count >= 2
    assert wait_ms >= 900
  end
end
