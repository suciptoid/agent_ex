defmodule AppWeb.OrganizationLive.SettingsTest do
  use AppWeb.ConnCase, async: false

  alias App.Organizations

  import App.AgentsFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "updates the organization default agent and preselects it for new chats", %{
    conn: conn,
    user: user,
    scope: scope
  } do
    first_agent = agent_fixture(user, %{name: "Planner"})
    second_agent = agent_fixture(user, %{name: "Researcher"})

    {:ok, live_view, _html} = live(conn, ~p"/organizations/settings")

    assert has_element?(live_view, "#organization-settings-page")
    assert has_element?(live_view, "#organization-settings-form")

    live_view
    |> form("#organization-settings-form", %{
      "settings" => %{"default_agent_id" => second_agent.id}
    })
    |> render_submit()

    assert Organizations.default_agent_id(scope) == second_agent.id

    {:ok, chat_live, _html} = live(conn, ~p"/chat")

    assert has_element?(chat_live, "#new-chat-agent-selector-set-#{second_agent.id}")
    refute has_element?(chat_live, "#new-chat-agent-selector-set-#{first_agent.id}")
  end
end
