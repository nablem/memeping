defmodule MemePing.Notifications.Worker do
  @moduledoc """
  One GenServer per enabled notifier: matches active tokens on the notifier's
  chain against its criteria/forbidden terms, sends unseen matches over
  Telegram, and records each delivery for permanent dedup.

  Ported from `Bentley.Notifiers.Worker`, minus sniper-triggering and
  `depends_on_notifier_ids` (no MemePing equivalent). Poll interval and batch
  size are fixed constants for v1 rather than per-notifier settings.

  Holds only the notifier's id as state and re-fetches it fresh from the DB on
  every poll tick, so edits to the notifier row *or* to its linked term list /
  Telegram channel take effect on the very next tick rather than requiring a
  worker restart.
  """
  use GenServer
  require Logger

  import Ecto.Query

  alias MemePing.Discovery.Token
  alias MemePing.Notifications
  alias MemePing.Notifications.Criteria
  alias MemePing.Notifications.Formatter
  alias MemePing.Notifications.NotificationDelivery
  alias MemePing.Notifications.Notifier
  alias MemePing.Repo
  alias MemePing.Telegram.Client

  @poll_interval :timer.minutes(1)
  @max_tokens_per_run 20

  def start_link(%Notifier{} = notifier) do
    GenServer.start_link(__MODULE__, notifier, name: via_tuple(notifier.id))
  end

  def child_spec(%Notifier{} = notifier) do
    %{
      id: {__MODULE__, notifier.id},
      start: {__MODULE__, :start_link, [notifier]},
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }
  end

  def via_tuple(id), do: {:via, Registry, {MemePing.Notifications.Registry, id}}

  @doc "Datetime of this worker's next scheduled poll, or `nil` if it isn't running."
  @spec next_poll_at(pos_integer()) :: NaiveDateTime.t() | nil
  def next_poll_at(id) do
    case Registry.lookup(MemePing.Notifications.Registry, id) do
      [{pid, _}] -> GenServer.call(pid, :next_poll_at)
      [] -> nil
    end
  end

  @doc "Runs a delivery pass right now instead of waiting for the next scheduled poll."
  @spec force_poll(pos_integer()) ::
          {:ok, %{matched: non_neg_integer(), sent: non_neg_integer(), failed: non_neg_integer()}}
          | {:error, :not_running}
  def force_poll(id) do
    case Registry.lookup(MemePing.Notifications.Registry, id) do
      [{pid, _}] -> GenServer.call(pid, :force_poll)
      [] -> {:error, :not_running}
    end
  end

  @spec deliver_notifications(Notifier.t(), NaiveDateTime.t()) ::
          {:ok, %{matched: non_neg_integer(), sent: non_neg_integer(), failed: non_neg_integer()}}
  def deliver_notifications(notifier, now \\ current_time())

  def deliver_notifications(%Notifier{telegram_channel_record: nil} = notifier, _now) do
    Logger.warning("[Notifiers] #{notifier.id} has no Telegram channel configured, skipping")
    {:ok, %{matched: 0, sent: 0, failed: 0}}
  end

  def deliver_notifications(%Notifier{} = notifier, now) do
    tokens = matching_tokens(notifier, now)

    result =
      Enum.reduce(tokens, %{matched: length(tokens), sent: 0, failed: 0}, fn token, acc ->
        case deliver_token(notifier, token, now) do
          :ok -> %{acc | sent: acc.sent + 1}
          {:error, _reason} -> %{acc | failed: acc.failed + 1}
        end
      end)

    {:ok, result}
  end

  @spec matching_tokens(Notifier.t(), NaiveDateTime.t()) :: [Token.t()]
  def matching_tokens(%Notifier{} = notifier, now \\ current_time()) do
    Token
    |> where([t], t.active == true and t.chain_id == ^notifier.chain)
    # Recorder can persist tokens before Updater enriches them; only notify checked tokens.
    |> where([t], not is_nil(t.last_checked_at))
    |> join(:left, [t], d in NotificationDelivery,
      on: d.token_address == t.token_address and d.notifier_id == ^notifier.id
    )
    |> where([_t, d], is_nil(d.id))
    |> select([t, _d], t)
    |> Repo.all()
    |> Enum.filter(&Notifications.token_matches?(notifier, &1, now))
    |> Enum.sort_by(&sort_key(&1, now), :asc)
    |> Enum.take(@max_tokens_per_run)
  end

  @impl true
  def init(%Notifier{id: id}) do
    {:ok, %{id: id, next_poll_at: schedule_poll(@poll_interval)}}
  end

  @impl true
  def handle_call(:next_poll_at, _from, state) do
    {:reply, state.next_poll_at, state}
  end

  @impl true
  def handle_call(:force_poll, _from, state) do
    {:reply, run_poll(state.id), state}
  end

  @impl true
  def handle_info(:poll, state) do
    run_poll(state.id)
    {:noreply, %{state | next_poll_at: schedule_poll(@poll_interval)}}
  end

  defp run_poll(id) do
    case Notifications.get_enabled_notifier(id) do
      nil ->
        {:ok, %{matched: 0, sent: 0, failed: 0}}

      notifier ->
        case deliver_notifications(notifier) do
          {:ok, %{matched: matched, sent: sent, failed: failed}} = result when matched > 0 ->
            Logger.info(
              "[Notifiers] #{notifier.id} evaluated #{matched} tokens, sent #{sent}, failed #{failed}"
            )

            result

          {:ok, _result} = result ->
            result
        end
    end
  end

  defp deliver_token(notifier, token, now) do
    message = Formatter.format(token, now)
    chat_id = notifier.telegram_channel_record.chat_id

    telegram_result =
      case token.icon do
        icon when is_binary(icon) -> Client.send_photo(chat_id, icon, message)
        _ -> Client.send_message(chat_id, message)
      end

    case telegram_result do
      :ok ->
        record_delivery(notifier, token, message, now)

      {:error, reason} ->
        Logger.error(
          "[Notifiers] Failed to send #{token.chain_id}/#{token.token_address} " <>
            "for notifier #{notifier.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp record_delivery(notifier, token, message, now) do
    %NotificationDelivery{}
    |> NotificationDelivery.changeset(%{
      notifier_id: notifier.id,
      chain_id: token.chain_id,
      token_address: token.token_address,
      telegram_channel: notifier.telegram_channel_record.chat_id,
      message_text: message,
      sent_at: now
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:notifier_id, :token_address])
    |> case do
      {:ok, _delivery} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp sort_key(token, now) do
    case Criteria.age_in_hours(token, now) do
      nil -> 1.0e308
      age_hours -> age_hours
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
    NaiveDateTime.add(current_time(), div(interval, 1_000), :second)
  end

  defp current_time, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
