defmodule MemePing.Repo.Migrations.CreateTokens do
  use Ecto.Migration

  def change do
    create table(:tokens) do
      add :chain_id, :string, null: false
      add :token_address, :string, null: false
      add :active, :boolean, null: false, default: true
      add :inactivity_reason, :string
      add :url, :string
      add :website_url, :string
      add :x_url, :string
      add :telegram_url, :string
      add :tiktok_url, :string
      add :instagram_url, :string
      add :discord_url, :string
      add :boost, :integer
      add :created_on_chain_at, :naive_datetime
      add :icon, :string
      add :description, :string
      add :market_cap, :float
      add :name, :string
      add :ticker, :string
      add :volume_1h, :float
      add :volume_6h, :float
      add :volume_24h, :float
      add :change_5m, :float
      add :change_1h, :float
      add :change_6h, :float
      add :change_24h, :float
      add :liquidity, :float
      add :ath, :float
      add :last_checked_at, :naive_datetime

      timestamps()
    end

    create unique_index(:tokens, [:chain_id, :token_address])
    create index(:tokens, [:active])
  end
end
