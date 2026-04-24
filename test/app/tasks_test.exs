defmodule App.TasksTest do
  use App.DataCase, async: false

  alias App.Chat
  alias App.Gateways
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

    test "bootstrap-runs repeat tasks immediately on first save", %{
      scope: scope,
      agent: agent
    } do
      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 "name" => "Immediate repeat",
                 "prompt" => "Run immediately",
                 "run_mode" => "repeat",
                 "schedule_type" => "every",
                 "every_interval" => "5",
                 "every_unit" => "minute",
                 "agent_ids" => [agent.id],
                 "main_agent_id" => agent.id
               })

      jobs = Repo.all(Oban.Job)

      assert Enum.any?(jobs, fn job ->
               job.worker == "App.Tasks.TaskRunWorker" and job.args["task_id"] == task.id
             end)

      assert task.next_run
    end

    test "bootstrap-runs cron repeat tasks and persists next_run", %{
      scope: scope,
      agent: agent
    } do
      assert {:ok, task} =
               Tasks.create_task(scope, %{
                 "name" => "Cron repeat",
                 "prompt" => "Run on cron",
                 "run_mode" => "repeat",
                 "schedule_type" => "cron",
                 "cron_expression" => "35 4 * * *",
                 "agent_ids" => [agent.id],
                 "main_agent_id" => agent.id
               })

      assert task.next_run
      assert task.schedule_type == :cron
      assert task.cron_expression == "35 4 * * *"
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
                 "last_run_at" => "2026-04-23T09:00:00Z",
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

  describe "update_task/3" do
    test "repairs repeat task next_run when editing and next_run is null", %{
      scope: scope,
      user: user,
      agent: agent
    } do
      task =
        task_fixture(user, %{
          agents: [agent],
          main_agent_id: agent.id,
          name: "Broken Cron",
          run_mode: "repeat",
          schedule_type: "cron",
          cron_expression: "35 4 * * *"
        })

      {:ok, broken_task} =
        task
        |> Ecto.Changeset.change(
          next_run: nil,
          last_run_at: ~U[2026-04-23 04:35:00.000000Z]
        )
        |> Repo.update()

      assert {:ok, updated_task} =
               Tasks.update_task(scope, broken_task, %{
                 "name" => "Broken Cron Updated",
                 "prompt" => task.prompt,
                 "run_mode" => "repeat",
                 "schedule_type" => "cron",
                 "cron_expression" => "35 4 * * *",
                 "agent_ids" => [agent.id],
                 "main_agent_id" => agent.id
               })

      assert updated_task.next_run
      assert DateTime.compare(updated_task.next_run, DateTime.utc_now()) == :gt
    end

    test "repairs repeat task next_run when editing and next_run is in the past", %{
      scope: scope,
      user: user,
      agent: agent
    } do
      task =
        task_fixture(user, %{
          agents: [agent],
          main_agent_id: agent.id,
          name: "Past Every",
          run_mode: "repeat",
          schedule_type: "every",
          every_interval: 1,
          every_unit: "day"
        })

      {:ok, broken_task} =
        task
        |> Ecto.Changeset.change(
          next_run: ~U[2026-04-01 00:00:00.000000Z],
          last_run_at: ~U[2026-03-31 00:00:00.000000Z]
        )
        |> Repo.update()

      assert {:ok, updated_task} =
               Tasks.update_task(scope, broken_task, %{
                 "name" => "Past Every Updated",
                 "prompt" => task.prompt,
                 "run_mode" => "repeat",
                 "schedule_type" => "every",
                 "every_interval" => "1",
                 "every_unit" => "day",
                 "agent_ids" => [agent.id],
                 "main_agent_id" => agent.id
               })

      assert updated_task.next_run
      assert DateTime.compare(updated_task.next_run, DateTime.utc_now()) == :gt
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

    test "relays final task output to linked notification channel and telegram", %{
      scope: scope,
      user: user,
      agent: agent
    } do
      previous_telegram_opts = Application.get_env(:app, App.Gateways.Telegram.Client)

      Application.put_env(:app, App.Gateways.Telegram.Client,
        req_options: [plug: {Req.Test, __MODULE__}]
      )

      on_exit(fn ->
        if previous_telegram_opts do
          Application.put_env(:app, App.Gateways.Telegram.Client, previous_telegram_opts)
        else
          Application.delete_env(:app, App.Gateways.Telegram.Client)
        end
      end)

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        send(self(), {:telegram_send_message, conn.request_path, payload})

        Req.Test.json(conn, %{"ok" => true, "result" => %{}})
      end)

      {:ok, gateway} =
        Gateways.create_gateway(scope, %{
          "name" => "Task Relay",
          "type" => "telegram",
          "token" => "telegram-token",
          "config" => %{"agent_id" => agent.id, "agent_ids" => [agent.id]}
        })

      {:ok, channel} =
        Gateways.find_or_create_channel(gateway, %{
          "external_chat_id" => "123456",
          "external_username" => "ops-room"
        })

      task =
        task_fixture(user, %{
          agents: [agent],
          main_agent_id: agent.id,
          name: "Digest Task",
          notification_chat_room_id: channel.chat_room_id
        })

      assert :ok = Tasks.run_task(task.id, "2026-04-24T09:00:00Z")

      notification_messages =
        channel.chat_room
        |> Chat.preload_chat_room()
        |> Chat.list_messages()

      assert Enum.any?(
               notification_messages,
               &(&1.role == "assistant" and &1.content == "Task Agent: #{task.prompt}")
             )

      assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", payload}
      assert payload["chat_id"] == "123456"
      assert payload["text"] =~ "Task Agent: #{task.prompt}"
    end
  end
end
