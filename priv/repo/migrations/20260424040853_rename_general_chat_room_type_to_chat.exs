defmodule App.Repo.Migrations.RenameGeneralChatRoomTypeToChat do
  use Ecto.Migration

  def up do
    execute("UPDATE chat_rooms SET type = 'chat' WHERE type = 'general'")

    alter table(:chat_rooms) do
      modify :type, :string, default: "chat", null: false
    end
  end

  def down do
    execute("UPDATE chat_rooms SET type = 'general' WHERE type = 'chat'")

    alter table(:chat_rooms) do
      modify :type, :string, default: "general", null: false
    end
  end
end
