defmodule MemePing.Notifications do
  @moduledoc """
  CRUD for a user's notifiers (Telegram destination + match criteria), plus
  the matching/delivery pipeline (`Worker`/`Manager`) that sends unseen
  matching tokens over Telegram.
  """

  import Ecto.Query

  alias MemePing.Accounts.User
  alias MemePing.Notifications.Criteria
  alias MemePing.Notifications.Notifier
  alias MemePing.Notifications.TermList
  alias MemePing.Notifications.Worker
  alias MemePing.Repo

  @spec list_notifiers(User.t()) :: [Notifier.t()]
  def list_notifiers(%User{id: user_id}) do
    Notifier
    |> where([n], n.user_id == ^user_id)
    |> preload([:telegram_channel_record, :term_list])
    |> order_by([n], asc: n.name)
    |> Repo.all()
  end

  @spec get_notifier!(User.t(), pos_integer() | String.t()) :: Notifier.t()
  def get_notifier!(%User{id: user_id}, id) do
    Notifier
    |> where([n], n.user_id == ^user_id)
    |> preload([:telegram_channel_record, :term_list])
    |> Repo.get!(id)
  end

  @spec new_notifier() :: Notifier.t()
  def new_notifier, do: %Notifier{criteria: %Criteria{}}

  @spec change_notifier(Notifier.t(), map()) :: Ecto.Changeset.t()
  def change_notifier(%Notifier{} = notifier, attrs \\ %{}) do
    Notifier.changeset(notifier, attrs)
  end

  @spec create_notifier(User.t(), map()) :: {:ok, Notifier.t()} | {:error, Ecto.Changeset.t()}
  def create_notifier(%User{id: user_id}, attrs) do
    %Notifier{}
    |> Notifier.changeset(Map.put(attrs, "user_id", user_id))
    |> Repo.insert()
    |> reconcile_notifiers()
  end

  @spec update_notifier(Notifier.t(), map()) :: {:ok, Notifier.t()} | {:error, Ecto.Changeset.t()}
  def update_notifier(%Notifier{} = notifier, attrs) do
    notifier
    |> Notifier.changeset(attrs)
    |> Repo.update()
    |> reconcile_notifiers()
  end

  @spec delete_notifier(Notifier.t()) :: {:ok, Notifier.t()} | {:error, Ecto.Changeset.t()}
  def delete_notifier(%Notifier{} = notifier) do
    notifier |> Repo.delete() |> reconcile_notifiers()
  end

  defp reconcile_notifiers({:ok, _notifier} = result) do
    MemePing.Notifications.Manager.reconcile()
    result
  end

  defp reconcile_notifiers(result), do: result

  @spec metrics() :: [{atom(), String.t()}]
  def metrics, do: Criteria.metrics()

  @doc """
  Chains at least one enabled notifier currently cares about.

  Queried live (no caching) so the Discovery pipeline picks up notifier
  creation/removal on its very next tick.
  """
  @spec active_chains() :: [String.t()]
  def active_chains do
    Notifier
    |> where([n], n.enabled == true)
    |> select([n], n.chain)
    |> distinct(true)
    |> Repo.all()
  end

  @spec list_enabled_notifiers() :: [Notifier.t()]
  def list_enabled_notifiers do
    Notifier
    |> where([n], n.enabled == true)
    |> preload([:telegram_channel_record, :term_list])
    |> Repo.all()
  end

  @doc """
  Fetches a notifier fresh from the DB (with its current criteria, term list,
  and Telegram channel), or `nil` if it's gone/disabled.

  Used by `Worker` on every poll tick instead of trusting its `init/1`
  snapshot, so edits to the notifier itself *or* to its linked term list /
  Telegram channel take effect on the very next tick, not just on the
  reconcile triggered by editing the notifier row.
  """
  @spec get_enabled_notifier(pos_integer()) :: Notifier.t() | nil
  def get_enabled_notifier(id) do
    Notifier
    |> where([n], n.id == ^id and n.enabled == true)
    |> preload([:telegram_channel_record, :term_list])
    |> Repo.one()
  end

  @doc """
  Whether `notifier` currently wants to be notified about `token`: every
  configured metric range matches, and neither the token's name nor ticker is
  flagged by the notifier's (optional) forbidden-terms list.
  """
  @spec token_matches?(Notifier.t(), struct() | map(), NaiveDateTime.t()) :: boolean()
  def token_matches?(%Notifier{} = notifier, token, now \\ NaiveDateTime.utc_now()) do
    Criteria.match?(token, notifier.criteria || %Criteria{}, now) and
      not TermList.match?(notifier.term_list, Map.get(token, :name)) and
      not TermList.match?(notifier.term_list, Map.get(token, :ticker))
  end

  @doc """
  Prints, for every notifier whose name contains `name` (case-insensitive),
  the tokens currently due to be sent on its next round, with metrics, plus
  when that next round is scheduled.

  For a quick eyeball check from `iex -S mix phx.server`:

      iex> MemePing.Notifications.recap("Solana calls")
  """
  @spec recap(String.t()) :: :ok
  def recap(name) do
    case find_notifiers_by_name(name) do
      [] -> IO.puts("No notifier matching #{inspect(name)}.")
      notifiers -> Enum.each(notifiers, &print_notifier_recap/1)
    end
  end

  @doc """
  Forces an immediate delivery pass for every notifier whose name contains
  `name` (case-insensitive), instead of waiting for its next scheduled round.
  Requires the notifier's worker to actually be running (`start_notifiers`
  enabled, notifier enabled + linked to a Telegram channel).

      iex> MemePing.Notifications.force_poll("Solana calls")
  """
  @spec force_poll(String.t()) :: :ok
  def force_poll(name) do
    case find_notifiers_by_name(name) do
      [] ->
        IO.puts("No notifier matching #{inspect(name)}.")

      notifiers ->
        Enum.each(notifiers, fn notifier ->
          case Worker.force_poll(notifier.id) do
            {:ok, result} ->
              IO.puts("#{notifier.name} (##{notifier.id}): #{inspect(result)}")

            {:error, :not_running} ->
              IO.puts("#{notifier.name} (##{notifier.id}): worker not running, skipped.")
          end
        end)
    end
  end

  defp find_notifiers_by_name(name) do
    Notifier
    |> where([n], like(fragment("lower(?)", n.name), fragment("lower(?)", ^"%#{name}%")))
    |> preload([:telegram_channel_record, :term_list])
    |> order_by([n], asc: n.name)
    |> Repo.all()
  end

  defp print_notifier_recap(notifier) do
    next_round =
      case Worker.next_poll_at(notifier.id) do
        nil -> "not running"
        datetime -> to_string(datetime)
      end

    IO.puts(
      "== #{notifier.name} (##{notifier.id}, #{notifier.chain}, " <>
        "#{if notifier.enabled, do: "enabled", else: "disabled"}) — next round: #{next_round} =="
    )

    notifier
    |> Worker.matching_tokens()
    |> print_tokens()
  end

  defp print_tokens([]), do: IO.puts("  (no tokens currently due)")

  defp print_tokens(tokens) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Enum.each(tokens, fn t ->
      age = Criteria.age_in_hours(t, now)

      IO.puts(
        "  #{pad(t.token_address, 46)} #{pad(t.ticker || "-", 10)} " <>
          "mcap=#{fmt(t.market_cap)} liq=#{fmt(t.liquidity)} vol1h=#{fmt(t.volume_1h)} " <>
          "age_h=#{fmt(age)}"
      )
    end)
  end

  defp pad(value, len), do: String.pad_trailing(to_string(value), len)
  defp fmt(nil), do: "-"
  defp fmt(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)
end
