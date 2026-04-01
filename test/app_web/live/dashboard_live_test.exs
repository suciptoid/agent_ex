defmodule AppWeb.DashboardLiveTest do
  use AppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders the floating mobile sidebar trigger and full-width content shell", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, ~p"/dashboard")

    assert has_element?(live_view, "#dashboard-layout")
    assert has_element?(live_view, "#dashboard-layout button[aria-label='Open sidebar']")
    assert has_element?(live_view, "#dashboard-layout main.w-full")
  end
end
