defmodule MemePing.Notifications.TermLists do
  @moduledoc """
  CRUD for reusable, case-insensitive forbidden regex lists.
  """

  import Ecto.Query

  alias MemePing.Accounts
  alias MemePing.Accounts.User
  alias MemePing.Notifications.TermList
  alias MemePing.Repo

  @spec list_term_lists(User.t()) :: [TermList.t()]
  def list_term_lists(%User{id: user_id}) do
    TermList
    |> where([term_list], term_list.user_id == ^user_id)
    |> order_by([term_list], asc: term_list.name)
    |> Repo.all()
  end

  @spec get_term_list!(User.t(), pos_integer() | String.t()) :: TermList.t()
  def get_term_list!(%User{id: user_id}, id) do
    TermList
    |> where([term_list], term_list.user_id == ^user_id)
    |> Repo.get!(id)
  end

  @spec new_term_list() :: TermList.t()
  def new_term_list, do: %TermList{}

  @spec change_term_list(TermList.t(), map()) :: Ecto.Changeset.t()
  def change_term_list(%TermList{} = term_list, attrs \\ %{}),
    do: TermList.changeset(term_list, attrs)

  @spec create_term_list(User.t(), map()) :: {:ok, TermList.t()} | {:error, Ecto.Changeset.t()}
  def create_term_list(%User{id: user_id} = user, attrs) do
    changeset = TermList.changeset(%TermList{}, Map.put(attrs, "user_id", user_id))

    if limit_reached?(user_id, Accounts.resource_limit(user, :term_list)) do
      {:error,
       limit_error(changeset, "forbidden term lists", Accounts.resource_limit(user, :term_list))}
    else
      Repo.insert(changeset)
    end
  end

  @spec update_term_list(TermList.t(), map()) ::
          {:ok, TermList.t()} | {:error, Ecto.Changeset.t()}
  def update_term_list(%TermList{} = term_list, attrs) do
    term_list
    |> TermList.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_term_list(TermList.t()) :: {:ok, TermList.t()} | {:error, Ecto.Changeset.t()}
  def delete_term_list(%TermList{} = term_list), do: Repo.delete(term_list)

  defp limit_reached?(_user_id, nil), do: false

  defp limit_reached?(user_id, limit) do
    Repo.aggregate(from(term_list in TermList, where: term_list.user_id == ^user_id), :count) >=
      limit
  end

  defp limit_error(changeset, resource, limit) do
    changeset
    |> Ecto.Changeset.add_error(:name, "Your plan allows up to #{limit} #{resource}.")
    |> Map.put(:action, :insert)
  end
end
