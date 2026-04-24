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
        "thinking_mode" => "enabled",
        "tools" => ["web_fetch", "create_tool"]
      }

      assert {:ok, agent} = Agents.create_agent(scope, attrs)
      assert agent.name == "Planner"
      assert agent.tools == ["web_fetch", "create_tool"]

      assert agent.extra_params == %{
               "max_tokens" => 512,
               "thinking" => "enabled",
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
          thinking_mode: "enabled"
        })

      changeset = Agents.change_agent(user_scope_fixture(user), agent)

      assert Ecto.Changeset.get_field(changeset, :temperature) == 0.6
      assert Ecto.Changeset.get_field(changeset, :max_tokens) == 1024
      assert Ecto.Changeset.get_field(changeset, :thinking_mode) == "enabled"
    end
  end

  describe "memory scoping" do
    test "org memories are shared across agents and stored without agent or user ids", %{
      user: user,
      scope: scope,
      provider: provider
    } do
      first_agent = agent_fixture(user, %{provider: provider, name: "Planner"})
      second_agent = agent_fixture(user, %{provider: provider, name: "Reviewer"})

      assert {:ok, memory} =
               Agents.set_memory(%{
                 "organization_id" => scope.organization.id,
                 "agent_id" => first_agent.id,
                 "user_id" => user.id,
                 "scope" => "org",
                 "key" => "release_window",
                 "value" => "Friday"
               })

      assert App.Agents.Memory.ownership(memory) == :org
      assert memory.agent_id == nil
      assert memory.user_id == nil

      assert {:ok, updated_memory} =
               Agents.set_memory(%{
                 "organization_id" => scope.organization.id,
                 "agent_id" => second_agent.id,
                 "scope" => "org",
                 "key" => "release_window",
                 "value" => "Monday"
               })

      assert updated_memory.id == memory.id

      assert %App.Agents.Memory{} =
               fetched =
               Agents.get_memory("org", "release_window",
                 organization_id: scope.organization.id,
                 user_id: user.id,
                 agent_id: second_agent.id
               )

      assert fetched.value == "Monday"
      assert App.Agents.Memory.ownership(fetched) == :org
      assert fetched.agent_id == nil
      assert fetched.user_id == nil
    end

    test "user memories are shared across agents for the same user", %{
      user: user,
      scope: scope,
      provider: provider
    } do
      first_agent = agent_fixture(user, %{provider: provider, name: "Planner"})
      second_agent = agent_fixture(user, %{provider: provider, name: "Reviewer"})

      assert {:ok, memory} =
               Agents.set_memory(%{
                 "organization_id" => scope.organization.id,
                 "agent_id" => first_agent.id,
                 "user_id" => user.id,
                 "scope" => "user",
                 "key" => "preferred_editor",
                 "value" => "Neovim"
               })

      assert App.Agents.Memory.ownership(memory) == :user
      assert memory.agent_id == nil
      assert memory.user_id == user.id

      assert %App.Agents.Memory{} =
               fetched =
               Agents.get_memory("user", "preferred_editor",
                 organization_id: scope.organization.id,
                 user_id: user.id,
                 agent_id: second_agent.id
               )

      assert fetched.id == memory.id
      assert fetched.value == "Neovim"
      assert App.Agents.Memory.ownership(fetched) == :user
    end

    test "prompt memories only include agent-scoped preferences", %{
      user: user,
      scope: scope,
      provider: provider
    } do
      agent = agent_fixture(user, %{provider: provider, name: "Planner"})

      {:ok, _org_memory} =
        Agents.set_memory(%{
          "organization_id" => scope.organization.id,
          "scope" => "org",
          "key" => "team_language",
          "value" => "English",
          "tags" => ["preferences"]
        })

      {:ok, _user_memory} =
        Agents.set_memory(%{
          "organization_id" => scope.organization.id,
          "user_id" => user.id,
          "scope" => "user",
          "key" => "user_timezone",
          "value" => "UTC",
          "tags" => ["preferences"]
        })

      {:ok, agent_memory} =
        Agents.set_memory(%{
          "organization_id" => scope.organization.id,
          "agent_id" => agent.id,
          "scope" => "agent",
          "key" => "style_guide",
          "value" => "Be concise",
          "tags" => ["preferences"]
        })

      memories = Agents.list_memories_for_prompt(agent.id, organization_id: scope.organization.id)

      assert Enum.map(memories, & &1.id) == [agent_memory.id]
      assert App.Agents.Memory.ownership(agent_memory) == :agent
    end
  end
end
