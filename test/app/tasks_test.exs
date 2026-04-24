defmodule App.TasksTest do
  use App.DataCase, async: false

  alias App.Chat
  alias App.Tasks

  import App.AgentsFixtures
  import App.ProvidersFixtures
  import App.TasksFixtures
  import App.UsersFixtures

  setup do
    previous_runner = Application.get_env(:app, :agent_runner)
    Application.put_env(:app, :agent_runner, App.TestSupport.PreloadedProviderRunnerStub)

    on_exit(fn ->
      if previous_runner do
        Application.put_env(:app, :agent_runner, previous_runner)
      else
        Application.delete_env(:app, :agent_runner)
      end
    end)

    user = user_fixture()
    scope = App.OrganizationsFixtures.organization_scope_fixture(user)
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Task Agent"})

    %{user: user, scope: scope, provider: provider, agent: agent}
  end

  describe "create_task/2" do
    test "stores selected agents and main agent", %{
      scope: scope,
      user: user,
      provider: provider,
      agent: agent
    } do
      second_agent = agent_fixture(user, %{provider: provider, name: "Backup Agent"})

      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 "name" => "Morning digest",
                 "prompt" => "Summarize the latest work",
                 "next_run_input" => "2026-04-24T09:00",
                 "agent_ids" => [agent.id, second_agent.id],
                 "main_agent_id" => second_agent.id,
                 "repeat" => "false"
               })

      assert Enum.sort(Enum.map(task.task_agents, & &1.agent_id)) ==
               Enum.sort([agent.id, second_agent.id])

      assert task.main_agent_id == second_agent.id
    end
  end

  describe "dispatch_due_tasks/1" do
    test "enqueues a worker job and advances the next run for repeating tasks", %{
      scope: scope,
      agent: agent
    } do
      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 "name" => "Weekly check-in",
                 "prompt" => "Check the queue",
                 "next_run_input" => "2026-04-24T09:00",
                 "agent_ids" => [agent.id],
                 "main_agent_id" => agent.id,
                 "repeat" => "true",
                 "schedule_type" => "every",
                 "every_interval" => "1",
                 "every_unit" => "day"
               })

      original_next_run = task.next_run
      :ok = Tasks.dispatch_due_tasks(~U[2026-04-24 09:00:00Z])

      refreshed_task = Tasks.get_task!(scope, task.id)
      assert refreshed_task.next_run > original_next_run

      jobs = Repo.all(Oban.Job)

      assert Enum.any?(
               jobs,
               &(&1.worker == "App.Tasks.TaskRunWorker" and &1.args["task_id"] == task.id)
             )
    end
  end

  describe "run_task/2" do
    test "creates a task chat room and saves the task transcript", %{
      scope: scope,
      user: user,
      agent: agent
    } do
      task = task_fixture(user, %{agents: [agent], main_agent_id: agent.id, name: "Digest Task"})

      assert :ok = Tasks.run_task(task.id, "2026-04-24T09:00:00Z")

      [task_room] = Chat.list_chat_rooms(scope, types: [:task])
      assert task_room.title =~ "Digest Task"

      messages = Chat.list_messages(task_room)
      assert Enum.any?(messages, &(&1.role == "user" and &1.content == task.prompt))

      assert Enum.any?(
               messages,
               &(&1.role == "assistant" and &1.content == "Task Agent: #{task.prompt}")
             )
    end
  end
end
