defmodule App.Repo.Migrations.AddToolMessageFieldsToChatMessages do
  use Ecto.Migration

  def change do
    alter table(:chat_messages) do
      add :name, :string
      add :tool_call_id, :string
      add :parent_message_id, references(:chat_messages, type: :binary_id, on_delete: :delete_all)
    end

    create index(:chat_messages, [:tool_call_id])
    create index(:chat_messages, [:parent_message_id])

    create unique_index(:chat_messages, [:parent_message_id, :tool_call_id],
             name: :chat_messages_parent_tool_call_id_index
           )
  end
end
