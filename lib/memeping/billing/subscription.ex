defmodule MemePing.Billing.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias MemePing.Accounts.User
  alias MemePing.Accounts.Plan

  schema "subscriptions" do
    belongs_to :user, User
    field :plan, :string
    field :started_on, :date
    field :expires_on, :date
    field :duration_days, :integer
    field :transaction_hash, :string
    field :payer_address, :string
    field :amount_usdc, :integer

    timestamps(updated_at: false)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :user_id,
      :plan,
      :started_on,
      :expires_on,
      :duration_days,
      :transaction_hash,
      :payer_address,
      :amount_usdc
    ])
    |> validate_required([
      :user_id,
      :plan,
      :started_on,
      :expires_on,
      :duration_days,
      :transaction_hash,
      :payer_address,
      :amount_usdc
    ])
    |> validate_inclusion(:plan, Plan.ids() -- ["free"])
    |> unique_constraint(:transaction_hash)
  end
end
