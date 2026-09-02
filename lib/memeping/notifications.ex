defmodule MemePing.Notifications do
  @moduledoc """
  CRUD for a user's notifiers (Telegram destination + match criteria).

  This is UI/data-capture only for now: nothing here polls DEX Screener or sends
  Telegram messages yet.
  """

  import Ecto.Query

  alias MemePing.Accounts.User
  alias MemePing.Notifications.Criteria
  alias MemePing.Notifications.Notifier
  alias MemePing.Notifications.TermList
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
end
