defmodule AppWeb.ProviderLiveTest do
  use AppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "new provider form lists library-backed providers", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, ~p"/providers/new")

    assert has_element?(live_view, "#provider-form")
    assert has_element?(live_view, "#provider-form [role=\"option\"][data-value=\"openai\"]")

    assert has_element?(
             live_view,
             "#provider-form [role=\"option\"][data-value=\"github_copilot\"]"
           )

    assert has_element?(live_view, "#provider-form [role=\"searchbox\"]")
  end
end
