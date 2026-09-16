defmodule MemePing.Billing.ExpiryWorker do
  use GenServer

  alias MemePing.Billing

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    Billing.expire_subscriptions()
    schedule_next_run()
    {:ok, state}
  end

  @impl true
  def handle_info(:expire_subscriptions, state) do
    Billing.expire_subscriptions()
    schedule_next_run()
    {:noreply, state}
  end

  defp schedule_next_run do
    midnight = DateTime.new!(Date.add(Date.utc_today(), 1), ~T[00:00:00], "Etc/UTC")

    Process.send_after(
      self(),
      :expire_subscriptions,
      DateTime.diff(midnight, DateTime.utc_now(), :millisecond)
    )
  end
end
