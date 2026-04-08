defmodule AppWeb.AgentLiveTest do
  use AppWeb.ConnCase, async: true

  alias App.Agents

  import App.AgentsFixtures
  import App.ProvidersFixtures
  import App.ToolsFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "index" do
    test "lists agents for the current user", %{conn: conn, user: user} do
      provider = provider_fixture(user, %{name: "Anthropic Sandbox", provider: "anthropic"})

      agent =
        agent_fixture(user, %{
          provider: provider,
          name: "Explorer",
          model: "anthropic:claude-haiku-4-5",
          tools: ["web_fetch"]
        })

      {:ok, live_view, _html} = live(conn, ~p"/agents")

      assert has_element?(live_view, "#agents[data-layout='single-column']")
      assert has_element?(live_view, "#agent-#{agent.id}")
      assert has_element?(live_view, "#new-agent-button")
      assert has_element?(live_view, "#edit-agent-#{agent.id}")
      assert has_element?(live_view, "#agent-provider-#{agent.id}", "Anthropic Sandbox")
      assert has_element?(live_view, "#agent-model-#{agent.id}", "claude-haiku-4-5")
      assert has_element?(live_view, "#agent-tools-count-#{agent.id}", "1")
      refute has_element?(live_view, "#agent-#{agent.id}", "web_fetch")
    end

    test "creates an agent from the dedicated new page", %{conn: conn, user: user, scope: scope} do
      provider = provider_fixture(user, %{name: "Anthropic Sandbox", provider: "anthropic"})
      custom_tool = tool_fixture(user, %{name: "brave_search"})
      {:ok, live_view, _html} = live(conn, ~p"/agents")

      assert {:error, {:live_redirect, %{to: to}}} =
               live_view
               |> element("#new-agent-button")
               |> render_click()

      assert to == "/agents/new"

      {:ok, form_view, _html} = live(conn, ~p"/agents/new")

      assert has_element?(form_view, "#agent-create-page")
      refute has_element?(form_view, "#agent-dialog")

      submit_result =
        form_view
        |> element("#agent-form")
        |> render_submit(%{
          "agent" => %{
            "name" => "Planner",
            "model" => "anthropic:claude-haiku-4-5",
            "provider_id" => provider.id,
            "temperature" => "0.4",
            "max_tokens" => "256",
            "tools" => ["", "web_fetch", custom_tool.name]
          }
        })

      assert_redirect(form_view, ~p"/agents")

      {:ok, redirected_view, _html} = follow_redirect(submit_result, conn, ~p"/agents")

      [created_agent] = Agents.list_agents(scope)
      assert created_agent.name == "Planner"
      assert has_element?(redirected_view, "#agent-#{created_agent.id}")
      assert has_element?(redirected_view, "#edit-agent-#{created_agent.id}")
      assert Enum.sort(created_agent.tools) == ["brave_search", "web_fetch"]
    end

    test "deletes an agent", %{conn: conn, user: user} do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Disposable"})

      {:ok, live_view, _html} = live(conn, ~p"/agents")
      assert has_element?(live_view, "#agent-#{agent.id}")

      live_view
      |> element("#delete-agent-#{agent.id}")
      |> render_click()

      refute has_element?(live_view, "#agent-#{agent.id}")
    end
  end
end
