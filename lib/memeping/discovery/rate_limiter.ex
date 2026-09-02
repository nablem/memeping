defmodule MemePing.Discovery.RateLimiter do
  @moduledoc """
  Throttles outbound DEX Screener requests to 60 requests/minute (1/sec) across
  the whole discovery pipeline (Recorder + Updater share this single limiter).

  Ported from `Bentley.RateLimiter`.
  """
  use GenServer

  @rate_ms 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes `func` once a slot is available, blocking the caller if needed.
  """
  def execute(func) do
    GenServer.call(__MODULE__, :acquire, :infinity)
    func.()
  end

  @impl true
  def init(_opts) do
    {:ok, %{last_request_at: nil}}
  end

  @impl true
  def handle_call(:acquire, _from, %{last_request_at: nil} = state) do
    {:reply, :ok, %{state | last_request_at: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_call(:acquire, _from, state) do
    now = System.monotonic_time(:millisecond)
    diff = now - state.last_request_at

    if diff < @rate_ms do
      Process.sleep(@rate_ms - diff)
      {:reply, :ok, %{state | last_request_at: System.monotonic_time(:millisecond)}}
    else
      {:reply, :ok, %{state | last_request_at: now}}
    end
  end
end
