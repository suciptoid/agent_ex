defmodule App.Repo.Migrations.AllowNullContentInChatMessages do
  use Ecto.Migration

  def change do
    alter table(:chat_messages) do
      modify :content, :text, null: true
    end
  end
end
