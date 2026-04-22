defmodule App.Repo.Migrations.CreateAgentMemories do
  use Ecto.Migration

  def change do
    create table(:agent_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :value, :text, null: false
      add :tags, {:array, :string}, default: [], null: false
      add :scope, :string, null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:agent_memories, [:agent_id, :key, :scope, :user_id],
        name: :agent_memories_unique_user_key_idx,
        where: "user_id IS NOT NULL"
      )
    )

    create(
      unique_index(:agent_memories, [:agent_id, :key, :scope],
        name: :agent_memories_unique_org_key_idx,
        where: "user_id IS NULL"
      )
    )

    create index(:agent_memories, [:agent_id, :scope])
    create index(:agent_memories, [:agent_id, :key])
    create index(:agent_memories, [:organization_id])

    execute(
      "CREATE INDEX agent_memories_tags_idx ON agent_memories USING gin (tags)",
      "DROP INDEX IF EXISTS agent_memories_tags_idx"
    )
  end
end
