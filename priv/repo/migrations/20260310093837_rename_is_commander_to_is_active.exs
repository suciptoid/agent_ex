defmodule App.Repo.Migrations.RenameIsCommanderToIsActive do
  use Ecto.Migration

  def change do
    rename table(:chat_room_agents), :is_commander, to: :is_active
  end
end
