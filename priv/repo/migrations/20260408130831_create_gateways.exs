defmodule App.Repo.Migrations.CreateGateways do
  use Ecto.Migration

  def change do
    create table(:gateways, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :token, :binary, null: false
      add :webhook_secret, :string, null: false
      add :config, :map, default: %{}, null: false
      add :status, :string, default: "active", null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:gateways, [:organization_id])
    create index(:gateways, [:type])

    create table(:gateway_channels, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_chat_id, :string, null: false
      add :external_user_id, :string
      add :external_username, :string
      add :status, :string, default: "active", null: false
      add :metadata, :map, default: %{}

      add :gateway_id, references(:gateways, type: :binary_id, on_delete: :delete_all),
        null: false

      add :chat_room_id, references(:chat_rooms, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:gateway_channels, [:gateway_id, :external_chat_id])
    create index(:gateway_channels, [:chat_room_id])
  end
end
