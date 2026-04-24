defmodule App.Repo.Migrations.RelaxAndRescopeAgentMemories do
  use Ecto.Migration

  def up do
    drop_if_exists index(:agent_memories, [:agent_id, :scope])
    drop_if_exists index(:agent_memories, [:agent_id, :key])
    drop_if_exists index(:agent_memories, [:organization_id])
    drop_if_exists index(:agent_memories, [:organization_id, :scope])
    drop_if_exists index(:agent_memories, [:organization_id, :user_id])
    drop_if_exists index(:agent_memories, [:organization_id, :agent_id])

    drop_if_exists index(:agent_memories, [:organization_id, :key],
                     name: :agent_memories_unique_org_key_idx
                   )

    drop_if_exists index(:agent_memories, [:organization_id, :user_id, :key],
                     name: :agent_memories_unique_user_key_idx
                   )

    drop_if_exists index(:agent_memories, [:organization_id, :agent_id, :key],
                     name: :agent_memories_unique_agent_key_idx
                   )

    drop_if_exists index(:agent_memories, [:agent_id, :key, :scope],
                     name: :agent_memories_unique_org_key_idx
                   )

    drop_if_exists index(:agent_memories, [:agent_id, :key, :scope, :user_id],
                     name: :agent_memories_unique_user_key_idx
                   )

    execute("ALTER TABLE agent_memories ALTER COLUMN agent_id DROP NOT NULL")

    execute("""
    UPDATE agent_memories
    SET agent_id = NULL
    WHERE scope IN ('org', 'user')
    """)

    execute("""
    DELETE FROM agent_memories
    WHERE id IN (
      SELECT id
      FROM (
        SELECT
          id,
          row_number() OVER (
            PARTITION BY organization_id, key, coalesce(user_id::text, ''), coalesce(agent_id::text, '')
            ORDER BY updated_at DESC, inserted_at DESC, id DESC
          ) AS row_number
        FROM agent_memories
        WHERE scope IN ('org', 'user', 'agent')
      ) deduped
      WHERE deduped.row_number > 1
    )
    """)

    create index(:agent_memories, [:organization_id, :user_id])
    create index(:agent_memories, [:organization_id, :agent_id])

    create(
      unique_index(:agent_memories, [:organization_id, :key],
        name: :agent_memories_unique_org_key_idx,
        where: "user_id IS NULL AND agent_id IS NULL"
      )
    )

    create(
      unique_index(:agent_memories, [:organization_id, :user_id, :key],
        name: :agent_memories_unique_user_key_idx,
        where: "user_id IS NOT NULL AND agent_id IS NULL"
      )
    )

    create(
      unique_index(:agent_memories, [:organization_id, :agent_id, :key],
        name: :agent_memories_unique_agent_key_idx,
        where: "agent_id IS NOT NULL AND user_id IS NULL"
      )
    )

    execute("ALTER TABLE agent_memories DROP COLUMN scope")
  end

  def down do
    raise "Irreversible migration"
  end
end
