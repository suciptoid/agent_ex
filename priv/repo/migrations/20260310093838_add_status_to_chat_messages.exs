defmodule App.Repo.Migrations.AddStatusToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:chat_messages) do
      add :status, :string, default: "completed", null: false
    end
  end
end
