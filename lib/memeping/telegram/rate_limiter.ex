defmodule MemePing.Telegram.RateLimiter do
  @moduledoc """
  Spaces outbound Telegram API requests across all notifier workers.

  The limiter is process-local and intended for a single-node deployment. It
  starts no more than 20 requests per second, leaving headroom below Telegram's
  bot-wide limit. It logs a per-minute summary of released requests, queue
  depth, and wait time so delivery pressure is visible in application logs.
  """
  use GenServer
  require Logger

  @request_interval_ms 50
  @report_interval_ms :timer.minutes(1)
  @slow_wait_ms :timer.seconds(5)

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    GenServer.start_link(__MODULE__, initial_state(opts), name: name)
  end

  @doc "Executes `func` once the next shared Telegram request slot is available."
  @spec execute((-> result)) :: result when result: term()
  def execute(func), do: execute(__MODULE__, func)

  @doc false
  @spec execute(GenServer.server(), (-> result)) :: result when result: term()
  def execute(server, func) do
    GenServer.call(server, {:acquire, now()}, :infinity)
    func.()
  end

  @doc false
  def stats(server \\ __MODULE__), do: GenServer.call(server, :stats)

  @impl true
  def init(state) do
    Process.send_after(self(), :report, @report_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:acquire, queued_at}, _from, %{last_request_at: nil} = state) do
    granted_at = now()
    state = record_request(state, queued_at, granted_at)
    {:reply, :ok, %{state | last_request_at: granted_at}}
  end

  def handle_call({:acquire, queued_at}, _from, state) do
    wait_ms = max(state.interval_ms - (now() - state.last_request_at), 0)

    if wait_ms > 0, do: Process.sleep(wait_ms)

    granted_at = now()
    state = record_request(state, queued_at, granted_at)
    {:reply, :ok, %{state | last_request_at: granted_at}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, Map.take(state, [:request_count, :peak_queue_depth, :max_wait_ms]), state}
  end

  @impl true
  def handle_info(:report, state) do
    log_report(state)
    Process.send_after(self(), :report, @report_interval_ms)

    {:noreply, %{state | request_count: 0, peak_queue_depth: 0, max_wait_ms: 0}}
  end

  defp initial_state(opts) do
    %{
      interval_ms: interval_ms(opts),
      last_request_at: nil,
      max_wait_ms: 0,
      peak_queue_depth: 0,
      request_count: 0
    }
  end

  defp record_request(state, queued_at, granted_at) do
    queue_depth = message_queue_length()
    wait_ms = granted_at - queued_at

    if wait_ms >= @slow_wait_ms do
      Logger.warning(
        "[Telegram Rate Limiter] Request waited #{wait_ms}ms for a send slot; " <>
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

  defp log_report(%{request_count: 0}), do: :ok

  defp log_report(state) do
    Logger.info(
      "[Telegram Rate Limiter] Last minute: released #{state.request_count} requests, " <>
        "peak queue #{state.peak_queue_depth}, max wait #{state.max_wait_ms}ms"
    )
  end

  defp message_queue_length do
    {:message_queue_len, length} = Process.info(self(), :message_queue_len)
    length
  end

  defp interval_ms(opts), do: Keyword.get(opts, :interval_ms, @request_interval_ms)
  defp now, do: System.monotonic_time(:millisecond)
end
