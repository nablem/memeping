defmodule MemePing.Notifications.Notifier do
  use Ecto.Schema
  import Ecto.Changeset

  alias MemePing.Accounts.User
  alias MemePing.Notifications.Criteria
  alias MemePing.Notifications.TermList
  alias MemePing.Telegram.Channel

  @type t :: %__MODULE__{}

  @chains ["solana", "ethereum", "base", "bsc", "tron"]

  schema "notifiers" do
    field :name, :string
    field :chain, :string
    field :enabled, :boolean, default: true
    field :telegram_channel, :string
    field :forbidden_term_list, :string
    belongs_to :user, User
    belongs_to :telegram_channel_record, Channel, foreign_key: :telegram_channel_id
    belongs_to :term_list, TermList

    embeds_one :criteria, Criteria, on_replace: :update

    timestamps()
  end

  @spec chains() :: [String.t()]
  def chains, do: @chains

  @doc false
  def changeset(notifier, attrs) do
    notifier
    |> cast(attrs, [
      :name,
      :chain,
      :enabled,
      :telegram_channel_id,
      :term_list_id,
      :user_id
    ])
    |> cast_embed(:criteria)
    |> validate_required([:name, :chain, :user_id])
    |> validate_length(:name, max: 25)
    |> validate_inclusion(:chain, @chains)
    |> unique_constraint(:name, name: :notifiers_user_id_name_index)
  end
end
