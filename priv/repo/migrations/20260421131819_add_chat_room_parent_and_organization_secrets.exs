defmodule App.Repo.Migrations.AddChatRoomParentAndOrganizationSecrets do
  use Ecto.Migration

  def change do
    alter table(:chat_rooms) do
      add :parent_id, references(:chat_rooms, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:chat_rooms, [:parent_id])

    create table(:organization_secrets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :value, :binary, null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:organization_secrets, [:organization_id])

    create unique_index(:organization_secrets, [:organization_id, :key],
             name: :organization_secrets_organization_id_key_index
           )
  end
end
