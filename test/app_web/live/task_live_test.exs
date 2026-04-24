defmodule AppWeb.TaskLiveTest do
  use AppWeb.ConnCase, async: false

  alias App.Gateways
  alias App.Tasks

  import App.AgentsFixtures
  import App.ProvidersFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "creates a scheduled task from the task form", %{conn: conn, user: user, scope: scope} do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Scheduler"})

    {:ok, live_view, _html} = live(conn, ~p"/tasks/new")

    params = %{
      "task" => %{
        "name" => "Daily digest",
        "prompt" => "Summarize the latest commits",
        "next_run_input" => "2026-04-24T09:00",
        "repeat" => "false",
        "agent_ids" => ["", agent.id],
        "main_agent_id" => agent.id,
        "notification_chat_room_id" => ""
      }
    }

    render_change(live_view, "validate", params)
    render_submit(live_view, "save", params)

    assert_redirect(live_view, "/tasks")

    [task] = Tasks.list_tasks(scope)
    assert task.name == "Daily digest"
    assert task.main_agent_id == agent.id
  end

  test "lists tasks on the index page", %{conn: conn, user: user} do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Scheduler"})

    task =
      App.TasksFixtures.task_fixture(user, %{
        agents: [agent],
        main_agent_id: agent.id,
        name: "Nightly task"
      })

    {:ok, live_view, _html} = live(conn, ~p"/tasks")

    assert has_element?(live_view, "#task-row-#{task.id}")
    assert has_element?(live_view, "#task-edit-link-#{task.id}", "Nightly task")
  end

  test "keeps select labels and values stable during validation", %{
    conn: conn,
    user: user,
    scope: scope
  } do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Planner"})

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Alerts",
        "type" => "telegram",
        "token" => "telegram-token",
        "config" => %{
          "agent_id" => agent.id,
          "agent_ids" => [agent.id]
        }
      })

    {:ok, channel} =
      Gateways.find_or_create_channel(gateway, %{
        "external_chat_id" => "team-alerts",
        "external_username" => "team-alerts"
      })

    {:ok, live_view, _html} = live(conn, ~p"/tasks/new")

    html =
      render_change(live_view, "validate", %{
        "task" => %{
          "name" => "Daily digest",
          "prompt" => "Summarize the latest commits",
          "next_run_input" => "2026-04-24T09:00",
          "repeat" => "true",
          "schedule_type" => "cron",
          "cron_expression" => "0 9 * * 1-5",
          "agent_ids" => ["", agent.id],
          "main_agent_id" => agent.id,
          "notification_chat_room_id" => channel.chat_room_id
        }
      })

    assert has_element?(
             live_view,
             "#task_main_agent_id option[value=\"#{agent.id}\"][selected]",
             "Planner"
           )

    assert has_element?(
             live_view,
             "#task_notification_chat_room_id option[value=\"#{channel.chat_room_id}\"][selected]",
             "#{channel.chat_room.title} (Gateway)"
           )

    assert has_element?(
             live_view,
             "#task_notification_chat_room_id option[value=\"#{channel.chat_room_id}\"]",
             "#{channel.chat_room.title} (Gateway)"
           )

    assert has_element?(live_view, "#task_schedule_type option[value=\"cron\"][selected]")
    assert has_element?(live_view, "#task_cron_expression")
    assert html =~ ">Planner<"
    assert html =~ "#{channel.chat_room.title} (Gateway)"
  end
end
