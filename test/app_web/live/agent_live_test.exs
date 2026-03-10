defmodule AppWeb.AgentLiveTest do
  use AppWeb.ConnCase, async: true

  import App.AgentsFixtures
  import App.ProvidersFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "index" do
    test "lists agents for the current user", %{conn: conn, user: user} do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Explorer"})

      {:ok, live_view, _html} = live(conn, ~p"/agents")

      assert has_element?(live_view, "#agent-#{agent.id}")
      assert has_element?(live_view, "#new-agent-button")
    end

    test "creates an agent", %{conn: conn, user: user, scope: scope} do
      provider = provider_fixture(user)
      {:ok, live_view, _html} = live(conn, ~p"/agents")

      live_view
      |> element("#new-agent-button")
      |> render_click()

      assert_patch(live_view, ~p"/agents/new")

      live_view
      |> element("#agent-form")
      |> render_submit(%{
        "agent" => %{
          "name" => "Planner",
          "model" => "anthropic:claude-haiku-4-5",
          "provider_id" => provider.id,
          "temperature" => "0.4",
          "max_tokens" => "256",
          "tools" => ["", "web_fetch"]
        }
      })

      assert_patch(live_view, ~p"/agents")

      [created_agent] = App.Agents.list_agents(scope)
      assert created_agent.name == "Planner"
      assert has_element?(live_view, "#agent-#{created_agent.id}")
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
