defmodule AppWeb.OrganizationLive.SelectTest do
  use AppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import App.OrganizationsFixtures
  import App.UsersFixtures

  alias App.Organizations

  test "creating an organization activates it and enters the workspace", %{conn: conn} do
    user = user_fixture()
    _first_org = organization_fixture(user, %{name: "Alpha"})
    _second_org = organization_fixture(user, %{name: "Beta"})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} =
      live(conn, ~p"/organizations/select?new=true")

    {:ok, switch_conn} =
      lv
      |> form("#organization-form", organization: %{name: "Gamma"})
      |> render_submit()
      |> follow_redirect(conn)

    gamma_org =
      user
      |> Organizations.list_memberships()
      |> Enum.find_value(fn membership ->
        if membership.organization.name == "Gamma", do: membership.organization
      end)

    assert gamma_org
    assert get_session(switch_conn, :active_organization_id) == gamma_org.id
    assert redirected_to(switch_conn) == ~p"/dashboard"

    dashboard_conn = get(recycle(switch_conn), ~p"/dashboard")

    assert html_response(dashboard_conn, 200) =~ "Dashboard"
  end
end
