defmodule AppWeb.ToolLive.CreateTest do
  use AppWeb.ConnCase, async: true

  import App.ToolsFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "creates a custom tool and lists it", %{conn: conn, scope: scope} do
    {:ok, live_view, _html} = live(conn, ~p"/tools/create")

    live_view
    |> element("#tool-form")
    |> render_submit(%{
      "tool" => %{
        "name" => "brave_search",
        "description" => "Search Brave",
        "endpoint" => "https://example.test/search",
        "http_method" => "get",
        "param_rows" => %{
          "0" => %{"name" => "query", "type" => "string", "source" => "llm", "value" => ""},
          "1" => %{
            "name" => "safe_search",
            "type" => "boolean",
            "source" => "fixed",
            "value" => "true"
          }
        },
        "header_rows" => %{
          "0" => %{"key" => "authorization", "value" => "Bearer brave-key"}
        }
      }
    })

    [tool] = App.Tools.list_tools(scope)
    assert tool.name == "brave_search"
    assert has_element?(live_view, "#saved-tool-#{tool.id}")
  end

  test "renders saved tools list", %{conn: conn, user: user} do
    tool = tool_fixture(user, %{name: "weather_lookup"})

    {:ok, live_view, _html} = live(conn, ~p"/tools/create")

    assert has_element?(live_view, "#saved-tool-#{tool.id}")
    assert has_element?(live_view, "#tool-form")
  end
end
