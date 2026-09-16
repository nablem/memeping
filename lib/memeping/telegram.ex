defmodule MemePing.Telegram do
  @moduledoc """
  CRUD for a user's Telegram channel destinations.

  Connectivity and test-message delivery are intentionally deferred.
  """

  import Ecto.Query

  alias MemePing.Accounts
  alias MemePing.Accounts.User
  alias MemePing.Repo
  alias MemePing.Telegram.Channel
  alias MemePing.Telegram.Client

  @spec list_channels(User.t()) :: [Channel.t()]
  def list_channels(%User{id: user_id}) do
    Channel
    |> where([channel], channel.user_id == ^user_id)
    |> order_by([channel], asc: channel.name)
    |> Repo.all()
  end

  @spec get_channel!(User.t(), pos_integer() | String.t()) :: Channel.t()
  def get_channel!(%User{id: user_id}, id) do
    Channel
    |> where([channel], channel.user_id == ^user_id)
    |> Repo.get!(id)
  end

  @spec new_channel() :: Channel.t()
  def new_channel, do: %Channel{}

  @spec change_channel(Channel.t(), map()) :: Ecto.Changeset.t()
  def change_channel(%Channel{} = channel, attrs \\ %{}), do: Channel.changeset(channel, attrs)

  @spec create_channel(User.t(), map()) :: {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def create_channel(%User{id: user_id} = user, attrs) do
    changeset = Channel.changeset(%Channel{}, Map.put(attrs, "user_id", user_id))

    if limit_reached?(user_id, Accounts.resource_limit(user, :telegram_channel)) do
      {:error,
       limit_error(
         changeset,
         "Telegram channels",
         Accounts.resource_limit(user, :telegram_channel)
       )}
    else
      Repo.insert(changeset)
    end
  end

  @spec update_channel(Channel.t(), map()) :: {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def update_channel(%Channel{} = channel, attrs) do
    channel
    |> Channel.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_channel(Channel.t()) :: {:ok, Channel.t()} | {:error, Ecto.Changeset.t()}
  def delete_channel(%Channel{} = channel), do: Repo.delete(channel)

  defp limit_reached?(_user_id, nil), do: false

  defp limit_reached?(user_id, limit) do
    Repo.aggregate(from(channel in Channel, where: channel.user_id == ^user_id), :count) >= limit
  end

  defp limit_error(changeset, resource, limit) do
    changeset
    |> Ecto.Changeset.add_error(:name, "Your plan allows up to #{limit} #{resource}.")
    |> Map.put(:action, :insert)
  end

  @spec send_test_message(Channel.t()) :: :ok | {:error, term()}
  def send_test_message(%Channel{chat_id: chat_id, name: name}) do
    Client.send_message(
      chat_id,
      "MemePing test message\n\nThis channel is ready to receive memecoin calls for #{name}."
    )
  end
end
