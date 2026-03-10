defmodule App.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :chat_room_id, references(:chat_rooms, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all)
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chat_messages, [:chat_room_id])
    create index(:chat_messages, [:agent_id])
    create unique_index(:chat_messages, [:chat_room_id, :position])
  end
end
