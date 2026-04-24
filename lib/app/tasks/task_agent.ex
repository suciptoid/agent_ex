defmodule App.Tasks.TaskAgent do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "scheduled_task_agents" do
    belongs_to :scheduled_task, App.Tasks.Task
    belongs_to :agent, App.Agents.Agent

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(task_agent, attrs) do
    task_agent
    |> cast(attrs, [:scheduled_task_id, :agent_id])
    |> validate_required([:scheduled_task_id, :agent_id])
    |> foreign_key_constraint(:scheduled_task_id)
    |> foreign_key_constraint(:agent_id)
    |> unique_constraint(:agent_id, name: :scheduled_task_agents_task_id_agent_id_index)
  end
end
