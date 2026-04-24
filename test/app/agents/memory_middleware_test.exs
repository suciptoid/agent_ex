defmodule App.Agents.MemoryMiddlewareTest do
  use App.DataCase, async: true

  alias Alloy.Agent.State
  alias App.Agents
  alias App.Agents.MemoryMiddleware

  import App.AgentsFixtures
  import App.ProvidersFixtures
  import App.UsersFixtures

  test "injects user and agent preferences with values, org memory keys only" do
    user = user_fixture()
    scope = App.OrganizationsFixtures.organization_scope_fixture(user)
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Memory Agent"})

    {:ok, _user_memory} =
      Agents.set_memory(%{
        "organization_id" => scope.organization.id,
        "user_id" => user.id,
        "scope" => "user",
        "key" => "preferred_tone",
        "value" => "friendly",
        "tags" => ["preferences"]
      })

    {:ok, _agent_memory} =
      Agents.set_memory(%{
        "organization_id" => scope.organization.id,
        "agent_id" => agent.id,
        "scope" => "agent",
        "key" => "response_style",
        "value" => "concise",
        "tags" => ["preferences"]
      })

    {:ok, _org_memory} =
      Agents.set_memory(%{
        "organization_id" => scope.organization.id,
        "scope" => "org",
        "key" => "project_codename",
        "value" => "Aurora",
        "tags" => ["profile"]
      })

    state =
      %State{
        config: %{
          context: %{
            organization_id: scope.organization.id,
            user_id: user.id,
            agent_id: agent.id
          },
          system_prompt: "Base prompt"
        }
      }

    result = MemoryMiddleware.call(:before_completion, state)
    prompt = result.config.system_prompt

    assert prompt =~ "### User Profile & Preferences"
    assert prompt =~ "**preferred_tone**: friendly"
    assert prompt =~ "### Agent Preferences"
    assert prompt =~ "**response_style**: concise"
    assert prompt =~ "### Org Memory Index (keys only)"
    assert prompt =~ "**project_codename**"
    refute prompt =~ "**project_codename**: Aurora"
  end
end
