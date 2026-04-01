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
    assert_redirect(live_view, ~p"/tools/list")
  end

  test "renders tools list page", %{conn: conn, user: user} do
    tool = tool_fixture(user, %{name: "weather_lookup"})

    {:ok, live_view, _html} = live(conn, ~p"/tools/list")

    assert has_element?(live_view, "#tool-#{tool.id}")
    assert has_element?(live_view, "#edit-tool-#{tool.id}")
    assert has_element?(live_view, "#new-tool-button")
  end

  test "edits a custom tool", %{conn: conn, user: user, scope: scope} do
    tool =
      tool_fixture(user, %{
        name: "reader",
        description: "Old",
        endpoint: "https://example.test/{dynamic_path}",
        param_rows: [
          %{"name" => "dynamic_path", "type" => "string", "source" => "llm", "value" => ""},
          %{"name" => "safe_search", "type" => "boolean", "source" => "fixed", "value" => "true"}
        ]
      })

    {:ok, live_view, _html} = live(conn, ~p"/tools/#{tool.id}/edit")

    live_view
    |> element("#tool-form")
    |> render_submit(%{
      "tool" => %{
        "name" => "reader",
        "description" => "Updated",
        "endpoint" => "https://example.test/{dynamic_path}?safe_search=true",
        "http_method" => "get",
        "param_rows" => %{
          "0" => %{"name" => "dynamic_path", "type" => "string", "source" => "llm", "value" => ""},
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

    updated_tool = App.Tools.get_tool!(scope, tool.id)
    assert updated_tool.description == "Updated"
    assert updated_tool.endpoint == "https://example.test/{dynamic_path}?safe_search=true"
  end
end
