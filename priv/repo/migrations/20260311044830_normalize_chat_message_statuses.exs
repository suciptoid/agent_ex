defmodule App.Repo.Migrations.NormalizeChatMessageStatuses do
  use Ecto.Migration

  def change do
    execute(
      "UPDATE chat_messages SET status = 'pending' WHERE status = 'requesting'",
      "UPDATE chat_messages SET status = 'requesting' WHERE status = 'pending'"
    )
  end
end
