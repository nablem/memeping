defmodule MemePing.Repo.Migrations.CreateNotificationDeliveries do
  use Ecto.Migration

  def change do
    create table(:notification_deliveries) do
      add :notifier_id, references(:notifiers, on_delete: :delete_all), null: false
      add :chain_id, :string, null: false
      add :token_address, :string, null: false
      add :telegram_channel, :string, null: false
      add :message_text, :string, null: false
      add :sent_at, :naive_datetime, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:notification_deliveries, [:notifier_id, :token_address])
  end
end
