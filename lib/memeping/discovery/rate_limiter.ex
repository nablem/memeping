defmodule MemePing.Discovery.RateLimiter do
  @moduledoc """
  Throttles outbound DEX Screener requests to 60 requests/minute (1/sec) across
  the whole discovery pipeline (Recorder + Updater share this single limiter).

  Ported from `Bentley.RateLimiter`.
  """
  use GenServer
  require Logger

  @rate_ms 1_000
  @report_interval_ms :timer.minutes(1)
  @slow_wait_ms :timer.seconds(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes `func` once a slot is available, blocking the caller if needed.
  """
  def execute(func) do
    GenServer.call(__MODULE__, {:acquire, now()}, :infinity)
    func.()
  end

  @doc false
  def stats, do: GenServer.call(__MODULE__, :stats)

  @impl true
  def init(_opts) do
    Process.send_after(self(), :report, @report_interval_ms)

    {:ok, %{last_request_at: nil, request_count: 0, peak_queue_depth: 0, max_wait_ms: 0}}
  end

  @impl true
  def handle_call({:acquire, queued_at}, _from, %{last_request_at: nil} = state) do
    granted_at = now()
    state = record_request(state, queued_at, granted_at)
    {:reply, :ok, %{state | last_request_at: granted_at}}
  end

  @impl true
  def handle_call({:acquire, queued_at}, _from, state) do
    diff = now() - state.last_request_at

    if diff < @rate_ms do
      Process.sleep(@rate_ms - diff)
    end

    granted_at = now()
    state = record_request(state, queued_at, granted_at)
    {:reply, :ok, %{state | last_request_at: granted_at}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, Map.take(state, [:request_count, :peak_queue_depth, :max_wait_ms]), state}
  end

  @impl true
  def handle_info(:report, state) do
    if state.request_count > 0 do
      Logger.info(
        "[DEX Screener Rate Limiter] Last minute: released #{state.request_count} requests, " <>
          "peak queue #{state.peak_queue_depth}, max wait #{state.max_wait_ms}ms"
      )
    end

    Process.send_after(self(), :report, @report_interval_ms)
    {:noreply, %{state | request_count: 0, peak_queue_depth: 0, max_wait_ms: 0}}
  end

  defp record_request(state, queued_at, granted_at) do
    queue_depth = message_queue_length()
    wait_ms = granted_at - queued_at

    if wait_ms >= @slow_wait_ms do
      Logger.warning(
        "[DEX Screener Rate Limiter] Request waited #{wait_ms}ms for a request slot; " <>
          "#{queue_depth} requests remain queued"
      )
    end

    %{
      state
      | request_count: state.request_count + 1,
        peak_queue_depth: max(state.peak_queue_depth, queue_depth),
        max_wait_ms: max(state.max_wait_ms, wait_ms)
    }
  end

  defp message_queue_length do
    {:message_queue_len, length} = Process.info(self(), :message_queue_len)
    length
  end

  defp now, do: System.monotonic_time(:millisecond)
end
