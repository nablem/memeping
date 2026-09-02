defmodule MemePing.Notifications.Manager do
  @moduledoc """
  Starts/stops one `Worker` per enabled (and Telegram-linked) notifier, kept in
  sync with the `notifiers` table.

  DB-backed equivalent of `Bentley.Notifiers`'s YAML-file reconciliation:
  instead of reloading from a file on a manual trigger, `reconcile/0` is
  called automatically after every notifier create/update/delete so changes
  take effect immediately, plus once at boot.
  """
  use GenServer
  require Logger

  alias MemePing.Notifications
  alias MemePing.Notifications.Worker

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Re-reads enabled notifiers from the DB and starts/stops workers to match."
  @spec reconcile() :: :ok
  def reconcile do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.call(__MODULE__, :reconcile, 30_000)
    end
  end

  @impl true
  def init(_state) do
    {:ok, apply_notifiers(%{notifiers: %{}})}
  end

  @impl true
  def handle_call(:reconcile, _from, state) do
    {:reply, :ok, apply_notifiers(state)}
  end

  defp apply_notifiers(state) do
    next_notifiers =
      Notifications.list_enabled_notifiers()
      |> Enum.filter(& &1.telegram_channel_record)
      |> Map.new(fn notifier -> {notifier.id, notifier} end)

    stop_removed_or_changed_workers(state.notifiers, next_notifiers)
    start_added_or_changed_workers(state.notifiers, next_notifiers)

    %{state | notifiers: next_notifiers}
  end

  defp stop_removed_or_changed_workers(current, next) do
    Enum.each(current, fn {id, notifier} ->
      case Map.get(next, id) do
        nil -> stop_worker(id)
        ^notifier -> :ok
        _updated -> stop_worker(id)
      end
    end)
  end

  defp start_added_or_changed_workers(current, next) do
    Enum.each(next, fn {id, notifier} ->
      case Map.get(current, id) do
        ^notifier -> :ok
        _previous -> start_worker(notifier)
      end
    end)
  end

  defp start_worker(notifier) do
    case DynamicSupervisor.start_child(
           MemePing.Notifications.DynamicSupervisor,
           {Worker, notifier}
         ) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("[Notifiers] Failed to start worker #{notifier.id}: #{inspect(reason)}")
    end
  end

  defp stop_worker(id) do
    case worker_pid(id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(MemePing.Notifications.DynamicSupervisor, pid)
    end
  end

  defp worker_pid(id) do
    case Registry.lookup(MemePing.Notifications.Registry, id) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end
end
