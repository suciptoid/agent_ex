defmodule App.ProvidersTest do
  use App.DataCase

  alias App.Providers
  alias App.UsersFixtures

  setup do
    user = UsersFixtures.user_fixture()
    scope = UsersFixtures.user_scope_fixture(user)
    {:ok, user: user, scope: scope}
  end

  describe "list_providers/1" do
    test "returns providers for the user", %{scope: scope, user: user} do
      provider = provider_fixture(user)
      assert Providers.list_providers(scope) == [provider]
    end

    test "returns empty list for user with no providers", %{scope: scope} do
      assert Providers.list_providers(scope) == []
    end
  end

  describe "create_provider/2" do
    test "creates provider with valid attrs", %{scope: scope} do
      attrs = %{
        "name" => "My Provider",
        "provider" => "openai",
        "api_key" => "sk-test"
      }

      assert {:ok, provider} = Providers.create_provider(scope, attrs)
      assert provider.name == "My Provider"
      assert provider.provider == "openai"
      assert provider.api_key == "sk-test"
    end

    test "accepts any provider name and infers type", %{scope: scope} do
      attrs = %{
        "name" => "Test",
        "provider" => "custom_llm",
        "api_key" => "key"
      }

      assert {:ok, provider} = Providers.create_provider(scope, attrs)
      assert provider.provider == "custom_llm"
      assert provider.provider_type == "openai_compat"
    end
  end

  describe "provider_options/0" do
    test "returns provider type options" do
      options = Providers.provider_options()
      assert {"anthropic", "Anthropic"} in options
      assert {"openai", "Openai"} in options
      assert {"openai_compat", "Openai Compat"} in options
    end
  end

  describe "delete_provider/2" do
    test "deletes provider owned by user", %{scope: scope, user: user} do
      provider = provider_fixture(user)
      assert {:ok, _} = Providers.delete_provider(scope, provider)
      assert Providers.list_providers(scope) == []
    end
  end

  defp provider_fixture(user, attrs \\ %{}) do
    {:ok, provider} =
      Providers.create_provider(
        UsersFixtures.user_scope_fixture(user),
        Map.merge(
          %{
            "provider" => "openai",
            "api_key" => "test-key"
          },
          attrs
        )
      )

    provider
  end
end
