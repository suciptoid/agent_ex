defmodule AppWeb.DashboardLiveTest do
  use AppWeb.ConnCase, async: true

  import App.AgentsFixtures
  import App.ChatFixtures
  import App.ProvidersFixtures
  import App.ToolsFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders an actionable empty workspace overview", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(live_view, "#dashboard-layout")
    assert has_element?(live_view, "#dashboard-layout button[aria-label='Open sidebar']")
    assert has_element?(live_view, "#dashboard-layout main.w-full")
    assert has_element?(live_view, "#dashboard-heading", "Dashboard")
    assert has_element?(live_view, "#dashboard-primary-action[href='/providers']")
    assert has_element?(live_view, "#dashboard-stat-providers-value", "0")
    assert has_element?(live_view, "#dashboard-stat-agents-value", "0")
    assert has_element?(live_view, "#dashboard-stat-tools-value", "0")
    assert has_element?(live_view, "#dashboard-stat-conversations-value", "0")
    assert has_element?(live_view, "#dashboard-empty-chats")
    assert has_element?(live_view, "#dashboard-empty-agents")
  end

  test "renders real workspace metrics and recent activity", %{conn: conn, user: user} do
    provider = provider_fixture(user, %{name: "Anthropic Sandbox", provider: "anthropic"})
    custom_tool = tool_fixture(user, %{name: "brave_search"})

    agent =
      agent_fixture(user, %{
        provider: provider,
        name: "Planner",
        model: "anthropic:claude-haiku-4-5",
        tools: ["web_fetch", custom_tool.name]
      })

    chat_room = chat_room_fixture(user, %{title: "Strategy Room", agents: [agent]})

    {:ok, live_view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(live_view, "#dashboard-stat-providers-value", "1")
    assert has_element?(live_view, "#dashboard-stat-agents-value", "1")
    assert has_element?(live_view, "#dashboard-stat-tools-value", "1")
    assert has_element?(live_view, "#dashboard-stat-conversations-value", "1")
    assert has_element?(live_view, "#recent-chat-#{chat_room.id}", "Strategy Room")
    assert has_element?(live_view, "#recent-agent-#{agent.id}", "Planner")
    assert has_element?(live_view, "#dashboard-primary-action[href='/chat']")
  end
end
