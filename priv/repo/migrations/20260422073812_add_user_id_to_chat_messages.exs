defmodule App.Repo.Migrations.AddUserIdToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:chat_messages) do
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:chat_messages, [:user_id])
  end
end
