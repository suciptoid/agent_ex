defmodule App.ProvidersFixtures do
  def provider_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "My OpenAI",
      provider: "openai",
      api_key: "sk-test-123456"
    })
  end

  def provider_fixture(user, attrs \\ %{}) do
    scope = App.OrganizationsFixtures.organization_scope_fixture(user)

    {:ok, provider} =
      App.Providers.create_provider(scope, provider_attrs(attrs))

    provider
  end
end
