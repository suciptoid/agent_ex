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
          "0" => %{"name" => "query", "type" => "string", "value" => ""},
          "1" => %{
            "name" => "safe_search",
            "type" => "boolean",
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

  test "creates a custom tool using inferred runtime and default parameter behavior", %{
    conn: conn,
    scope: scope
  } do
    {:ok, live_view, _html} = live(conn, ~p"/tools/create")

    live_view
    |> element("#tool-form")
    |> render_submit(%{
      "tool" => %{
        "name" => "example_reader",
        "description" => "Read a resource",
        "endpoint" => "https://api.example.com/{path_a}?q=param_a",
        "http_method" => "get",
        "param_rows" => %{
          "0" => %{"name" => "path_a", "type" => "string", "value" => ""},
          "1" => %{"name" => "param_a", "type" => "string", "value" => "default-query"}
        },
        "header_rows" => %{
          "0" => %{"key" => "authorization", "value" => "Bearer brave-key"}
        }
      }
    })

    [tool] = App.Tools.list_tools(scope)
    path_a = Enum.find(App.Tools.Tool.parameter_items(tool), &(&1["name"] == "path_a"))
    param_a = Enum.find(App.Tools.Tool.parameter_items(tool), &(&1["name"] == "param_a"))

    assert path_a["source"] == "llm"
    assert param_a["source"] == "fixed"
    assert param_a["value"] == "default-query"
  end

  test "renders tools list page", %{conn: conn, user: user} do
    tool = tool_fixture(user, %{name: "weather_lookup"})

    {:ok, live_view, _html} = live(conn, ~p"/tools/list")

    assert has_element?(live_view, "#tool-#{tool.id}")
    assert has_element?(live_view, "#edit-tool-#{tool.id}")
    assert has_element?(live_view, "#new-tool-button")
  end

  test "renders a compact tools list and deletes a tool", %{conn: conn, user: user} do
    tool = tool_fixture(user, %{name: "weather_lookup"})

    {:ok, live_view, _html} = live(conn, ~p"/tools/list")

    assert has_element?(live_view, "#tools.rounded-lg")
    assert has_element?(live_view, "#tool-#{tool.id}")
    assert has_element?(live_view, "#edit-tool-#{tool.id}")
    assert has_element?(live_view, "#delete-tool-#{tool.id}")

    live_view
    |> element("#delete-tool-#{tool.id}")
    |> render_click()

    refute has_element?(live_view, "#tool-#{tool.id}")
  end

  test "renders the simplified shared form and locks the method after naming the tool", %{
    conn: conn
  } do
    {:ok, live_view, _html} = live(conn, ~p"/tools/create")

    refute has_element?(live_view, "span", "HTTP Tool Builder")
    refute has_element?(live_view, "a", "Back to tool list")
    refute has_element?(live_view, "h2", "Template example")
    refute has_element?(live_view, "label", "Filled by")
    assert has_element?(live_view, "label", "Default value")
    refute render(live_view) =~ "https://r.jina.ai/{dynamic_path}?param_a=value"
    assert render(live_view) =~ "https://api.example.com/{path_a}?q=param_a"
    assert has_element?(live_view, "#tool-http-method:not([disabled])")

    live_view
    |> element("#tool-form")
    |> render_change(%{"tool" => %{"name" => "reader"}})

    assert has_element?(live_view, "#tool-http-method[disabled]")
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
          "0" => %{"name" => "dynamic_path", "type" => "string", "value" => ""},
          "1" => %{
            "name" => "safe_search",
            "type" => "boolean",
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
