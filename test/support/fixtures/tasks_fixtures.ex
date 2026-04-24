defmodule App.TasksFixtures do
  alias App.AgentsFixtures

  def task_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Scheduled Task",
      prompt: "Summarize the latest work",
      next_run_input: "2026-04-24T09:00",
      repeat: false
    })
  end

  def task_fixture(user, attrs \\ %{}) do
    attrs = Map.new(attrs)

    agents =
      Map.get(attrs, :agents) ||
        Map.get(attrs, "agents") ||
        [AgentsFixtures.agent_fixture(user)]

    agent_ids = Enum.map(agents, & &1.id)

    main_agent_id =
      Map.get(attrs, :main_agent_id) || Map.get(attrs, "main_agent_id") || List.first(agent_ids)

    params =
      attrs
      |> Map.delete(:agents)
      |> Map.delete("agents")
      |> task_attrs()
      |> Map.put(:agent_ids, agent_ids)
      |> Map.put(:main_agent_id, main_agent_id)

    {:ok, task} =
      App.Tasks.create_task(
        App.OrganizationsFixtures.organization_scope_fixture(user),
        params
      )

    task
  end
end
