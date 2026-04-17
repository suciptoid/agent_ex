defmodule App.AgentsFixtures do
  alias App.ProvidersFixtures

  def agent_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Helpful Agent",
      system_prompt: "You are a helpful assistant.",
      model: "claude-haiku-4-5",
      temperature: 0.3,
      max_tokens: 256,
      tools: []
    })
  end

  def agent_fixture(user, attrs \\ %{}) do
    attrs = Map.new(attrs)

    provider =
      case Map.get(attrs, :provider) || Map.get(attrs, "provider") do
        nil -> ProvidersFixtures.provider_fixture(user)
        provider -> provider
      end

    params =
      attrs
      |> Map.delete(:provider)
      |> Map.delete("provider")
      |> agent_attrs()
      |> Map.put(:provider_id, provider.id)

    {:ok, agent} =
      App.Agents.create_agent(
        App.OrganizationsFixtures.organization_scope_fixture(user),
        params
      )

    agent
  end
end
