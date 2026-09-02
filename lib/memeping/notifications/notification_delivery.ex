defmodule MemePing.Notifications.NotificationDelivery do
  @moduledoc """
  Dedup ledger: one row per (notifier, token) ever successfully delivered.

  Persisted in the database (not in-memory), so it survives app restarts and
  keeps a notifier from ever re-sending the same token twice.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MemePing.Notifications.Notifier

  @type t :: %__MODULE__{}

  schema "notification_deliveries" do
    field :chain_id, :string
    field :token_address, :string
    field :telegram_channel, :string
    field :message_text, :string
    field :sent_at, :naive_datetime
    belongs_to :notifier, Notifier

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :notifier_id,
      :chain_id,
      :token_address,
      :telegram_channel,
      :message_text,
      :sent_at
    ])
    |> validate_required([
      :notifier_id,
      :chain_id,
      :token_address,
      :telegram_channel,
      :message_text,
      :sent_at
    ])
    |> unique_constraint([:notifier_id, :token_address])
  end
end
