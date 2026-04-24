defmodule App.Repo.Migrations.AddChatRoomTypeAndScheduledTasks do
  use Ecto.Migration

  def change do
    alter table(:chat_rooms) do
      add :type, :string, default: "general", null: false
    end

    create index(:chat_rooms, [:organization_id, :type])

    create table(:scheduled_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :prompt, :text, null: false
      add :next_run, :utc_datetime_usec
      add :repeat, :boolean, default: false, null: false
      add :schedule_type, :string, default: "once", null: false
      add :cron_expression, :string
      add :every_interval, :integer
      add :every_unit, :string
      add :last_run_at, :utc_datetime_usec

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :main_agent_id, references(:agents, type: :binary_id), null: false

      add :notification_chat_room_id,
          references(:chat_rooms, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:scheduled_tasks, [:organization_id])
    create index(:scheduled_tasks, [:organization_id, :next_run])
    create index(:scheduled_tasks, [:main_agent_id])
    create index(:scheduled_tasks, [:notification_chat_room_id])

    create table(:scheduled_task_agents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :scheduled_task_id,
          references(:scheduled_tasks, type: :binary_id, on_delete: :delete_all), null: false

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:scheduled_task_agents, [:scheduled_task_id])

    create unique_index(:scheduled_task_agents, [:scheduled_task_id, :agent_id],
             name: :scheduled_task_agents_task_id_agent_id_index
           )
  end
end
