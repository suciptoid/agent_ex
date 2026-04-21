defmodule AppWeb.ProviderLiveTest do
  use AppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "new provider form uses only the provider field", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, ~p"/providers/new")

    assert has_element?(live_view, "#provider-form")
    assert has_element?(live_view, "#provider-form [role=\"option\"][data-value=\"openai\"]")
    assert has_element?(live_view, "#provider-form [role=\"option\"][data-value=\"anthropic\"]")

    assert has_element?(
             live_view,
             "#provider-form [role=\"option\"][data-value=\"openai_compat\"]"
           )

    refute has_element?(live_view, "#provider-form [name=\"provider[provider_type]\"]")
  end
end
