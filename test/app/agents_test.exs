defmodule App.AgentsTest do
  use App.DataCase, async: true

  alias App.Agents

  import App.AgentsFixtures
  import App.ProvidersFixtures
  import App.ToolsFixtures
  import App.UsersFixtures

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)
    provider = provider_fixture(user)

    %{user: user, scope: scope, provider: provider}
  end

  describe "list_agents/1" do
    test "returns only agents owned by the current user", %{
      scope: scope,
      user: user,
      provider: provider
    } do
      agent = agent_fixture(user, %{provider: provider, name: "Personal Agent"})

      other_user = user_fixture()
      other_provider = provider_fixture(other_user)
      _other_agent = agent_fixture(other_user, %{provider: other_provider, name: "Other Agent"})

      assert [listed_agent] = Agents.list_agents(scope)
      assert listed_agent.id == agent.id
      assert listed_agent.provider.id == provider.id
    end
  end

  describe "create_agent/2" do
    test "creates an agent with extra params and tools", %{scope: scope, provider: provider} do
      attrs = %{
        "name" => "Planner",
        "system_prompt" => "Plan carefully.",
        "model" => "claude-haiku-4-5",
        "provider_id" => provider.id,
        "temperature" => "0.4",
        "max_tokens" => "512",
        "reasoning_effort" => "high",
        "tools" => ["web_fetch", "create_tool"]
      }

      assert {:ok, agent} = Agents.create_agent(scope, attrs)
      assert agent.name == "Planner"
      assert agent.tools == ["web_fetch", "create_tool"]

      assert agent.extra_params == %{
               "max_tokens" => 512,
               "reasoning_effort" => "high",
               "temperature" => 0.4
             }

      assert agent.provider.id == provider.id
    end

    test "creates an agent with a custom user tool", %{
      scope: scope,
      provider: provider,
      user: user
    } do
      tool = tool_fixture(user, %{name: "brave_search"})

      assert {:ok, agent} =
               Agents.create_agent(scope, %{
                 "name" => "Searcher",
                 "model" => "claude-haiku-4-5",
                 "provider_id" => provider.id,
                 "tools" => [tool.name, "web_fetch"]
               })

      assert Enum.sort(agent.tools) == ["brave_search", "web_fetch"]
    end

    test "rejects providers owned by another user", %{scope: scope} do
      other_provider = provider_fixture(user_fixture())

      assert {:error, changeset} =
               Agents.create_agent(scope, %{
                 "name" => "Blocked",
                 "model" => "claude-haiku-4-5",
                 "provider_id" => other_provider.id
               })

      assert "must belong to the current organization" in errors_on(changeset).provider_id
    end
  end

  describe "update_agent/3" do
    test "updates an owned agent", %{scope: scope, user: user, provider: provider} do
      agent = agent_fixture(user, %{provider: provider, name: "Writer"})

      assert {:ok, updated_agent} =
               Agents.update_agent(scope, agent, %{
                 "name" => "Editor",
                 "tools" => ["web_fetch"]
               })

      assert updated_agent.name == "Editor"
      assert updated_agent.tools == ["web_fetch"]
    end
  end

  describe "delete_agent/2" do
    test "deletes an owned agent", %{scope: scope, user: user, provider: provider} do
      agent = agent_fixture(user, %{provider: provider})

      assert {:ok, _agent} = Agents.delete_agent(scope, agent)
      assert Agents.list_agents(scope) == []
    end
  end

  describe "change_agent/2" do
    test "preloads virtual extra params for forms", %{user: user, provider: provider} do
      agent =
        agent_fixture(user, %{
          provider: provider,
          temperature: 0.6,
          max_tokens: 1024,
          reasoning_effort: "low"
        })

      changeset = Agents.change_agent(user_scope_fixture(user), agent)

      assert Ecto.Changeset.get_field(changeset, :temperature) == 0.6
      assert Ecto.Changeset.get_field(changeset, :max_tokens) == 1024
      assert Ecto.Changeset.get_field(changeset, :reasoning_effort) == "low"
    end
  end
end
