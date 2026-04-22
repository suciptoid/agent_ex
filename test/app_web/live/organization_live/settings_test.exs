defmodule AppWeb.OrganizationLive.SettingsTest do
  use AppWeb.ConnCase, async: false

  alias App.Gateways
  alias App.Organizations

  import App.AgentsFixtures
  import App.OrganizationsFixtures
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

  test "adds an existing user to the organization with the selected role", %{
    conn: conn,
    organization: organization
  } do
    teammate = App.UsersFixtures.user_fixture(%{email: "teammate@example.com", name: "Teammate"})

    {:ok, live_view, _html} = live(conn, ~p"/organizations/settings")

    live_view
    |> element("#open-add-member-modal-button")
    |> render_click()

    assert has_element?(live_view, "#organization-member-dialog")
    assert has_element?(live_view, "#organization-member-form")

    live_view
    |> form("#organization-member-form", %{
      "member" => %{
        "email" => teammate.email,
        "role" => "admin"
      }
    })
    |> render_submit()

    memberships = Organizations.list_memberships(teammate)

    assert Enum.any?(memberships, fn membership ->
             membership.organization_id == organization.id and membership.role == "admin"
           end)

    assert has_element?(live_view, "#organization-settings-page", "Members")
    assert has_element?(live_view, "td", teammate.email)
    assert has_element?(live_view, "td", "admin")
  end

  test "channel user mappings render member name and email instead of the raw user id", %{
    conn: conn,
    user: user,
    scope: scope,
    organization: organization
  } do
    teammate = App.UsersFixtures.user_fixture(%{email: "mapped@example.com", name: "Mapped User"})
    _membership = membership_fixture(teammate, organization, "member")

    Organizations.put_secret_value(scope, "channel_user_map:telegram:5678", teammate.id)

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Mapped Bot",
        "type" => "telegram",
        "token" => "mapping-token",
        "status" => "inactive"
      })

    {:ok, _channel} =
      Gateways.find_or_create_channel(gateway, %{
        external_chat_id: "1234",
        external_user_id: "5678",
        external_username: "mapped_user"
      })

    {:ok, live_view, _html} = live(conn, ~p"/organizations/settings")

    assert has_element?(live_view, "td", "Mapped User (mapped@example.com)")
    refute render(live_view) =~ teammate.id
    refute render(live_view) =~ "#{user.id}</td>"
  end
end
