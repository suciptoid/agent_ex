defmodule App.Repo.Migrations.CreateChatRoomAgents do
  use Ecto.Migration

  def change do
    create table(:chat_room_agents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :chat_room_id, references(:chat_rooms, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
      add :is_commander, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chat_room_agents, [:chat_room_id])
    create index(:chat_room_agents, [:agent_id])
    create unique_index(:chat_room_agents, [:chat_room_id, :agent_id])
  end
end
