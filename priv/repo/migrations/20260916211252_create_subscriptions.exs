defmodule MemePing.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan, :string, null: false
      add :started_on, :date, null: false
      add :expires_on, :date, null: false
      add :duration_days, :integer, null: false
      add :transaction_hash, :string, null: false
      add :payer_address, :string, null: false
      add :amount_usdc, :integer, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:subscriptions, [:transaction_hash])
    create index(:subscriptions, [:user_id, :expires_on])
  end
end
