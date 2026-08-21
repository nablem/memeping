defmodule MemePing.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias MemePing.Accounts.Plan
  alias MemePing.Accounts.WalletIdentity

  @type t :: %__MODULE__{}

  schema "users" do
    field :plan, :string, default: "free"
    has_many :wallet_identities, WalletIdentity

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    cast(user, attrs, [])
  end

  @doc false
  def plan_changeset(user, attrs) do
    user
    |> cast(attrs, [:plan])
    |> validate_required([:plan])
    |> validate_inclusion(:plan, Plan.ids())
  end
end
