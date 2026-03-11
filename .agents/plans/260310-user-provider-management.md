# User Provider Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add user LLM provider management with encrypted API keys and install Jido agent framework.

**Architecture:** Create a `providers` context module with CRUD operations for user LLM providers. Use `cloak_ecto` for API key encryption (Note: `ecto_vault` doesn't exist on hex.pm - `cloak_ecto` is the standard Elixir library for Ecto field encryption). Install Jido for agent capabilities.

**Tech Stack:** Ecto, cloak_ecto (encryption), jido (agents), Phoenix LiveView

---

## Task 1: Install Dependencies

**Files:**
- Modify: `mix.exs:41-72`
- Modify: `config/config.exs`
- Modify: `config/dev.exs`
- Modify: `config/runtime.exs`
- Create: `lib/app/vault.ex`
- Modify: `lib/app/application.ex:10-19`

**Step 1: Add dependencies to mix.exs**

Add to deps function:
```elixir
{:cloak_ecto, "~> 1.3"},
{:jido, "~> 2.0"}
```

**Step 2: Run mix deps.get**

Run: `mix deps.get`
Expected: Dependencies fetched successfully

**Step 3: Generate encryption key**

Run: `iex -e "IO.puts(32 |> :crypto.strong_rand_bytes() |> Base.encode64())" --eval "System.halt(0)"`
Expected: A base64 encoded 32-byte key printed

**Step 4: Create Vault module**

Create `lib/app/vault.ex`:
```elixir
defmodule App.Vault do
  use Cloak.Vault, otp_app: :app

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers, [
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: decode_env!("ENCRYPTION_KEY")}
      ])

    {:ok, config}
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end
end
```

**Step 5: Add Vault to supervision tree**

Modify `lib/app/application.ex`, add `App.Vault` to children:
```elixir
children = [
  AppWeb.Telemetry,
  App.Repo,
  {DNSCluster, query: Application.get_env(:app, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: App.PubSub},
  App.Vault,
  AppWeb.Endpoint
]
```

**Step 6: Add encryption key to dev config**

Add to `config/dev.exs`:
```elixir
config :app, App.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!("dev_key_32_bytes_placeholder_replace_me!!")}
  ]
```

**Step 7: Create Jido instance module**

Create `lib/app/jido.ex`:
```elixir
defmodule App.Jido do
  use Jido, otp_app: :app
end
```

**Step 8: Configure Jido**

Add to `config/config.exs`:
```elixir
config :app, App.Jido,
  max_tasks: 1000,
  agent_pools: []
```

**Step 9: Add Jido to supervision tree**

Modify `lib/app/application.ex`, add `App.Jido` after `App.Vault`:
```elixir
children = [
  AppWeb.Telemetry,
  App.Repo,
  {DNSCluster, query: Application.get_env(:app, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: App.PubSub},
  App.Vault,
  App.Jido,
  AppWeb.Endpoint
]
```

**Step 10: Commit dependencies setup**

```bash
git add mix.exs mix.lock config/*.exs lib/app/vault.ex lib/app/jido.ex lib/app/application.ex
git commit -m "feat: add cloak_ecto and jido dependencies"
```

---

## Task 2: Create Encrypted Types

**Files:**
- Create: `lib/app/encrypted/binary.ex`

**Step 1: Create encrypted binary type**

Create `lib/app/encrypted/binary.ex`:
```elixir
defmodule App.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: App.Vault
end
```

**Step 2: Commit encrypted types**

```bash
git add lib/app/encrypted/binary.ex
git commit -m "feat: add encrypted binary type for cloak_ecto"
```

---

## Task 3: Create Provider Schema and Migration

**Files:**
- Create: `priv/repo/migrations/YYYYMMDDHHMMSS_create_providers.exs`
- Create: `lib/app/providers/provider.ex`

**Step 1: Generate migration**

Run: `mix ecto.gen.migration create_providers`
Expected: New migration file created

**Step 2: Write migration**

Replace migration content with:
```elixir
defmodule App.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :provider, :string, null: false
      add :api_key, :binary, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:providers, [:user_id])
    create index(:providers, [:user_id, :provider])
  end
end
```

**Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully

**Step 4: Create Provider schema**

Create `lib/app/providers/provider.ex`:
```elixir
defmodule App.Providers.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "providers" do
    field :name, :string
    field :provider, :string
    field :api_key, App.Encrypted.Binary

    belongs_to :user, App.Users.User

    timestamps(type: :utc_datetime)
  end

  @valid_providers ~w(openai anthropic google gemini mistral cohere)

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :provider, :api_key, :user_id])
    |> validate_required([:provider, :api_key, :user_id])
    |> validate_inclusion(:provider, @valid_providers)
    |> foreign_key_constraint(:user_id)
  end
end
```

**Step 5: Commit schema and migration**

```bash
git add priv/repo/migrations/*_create_providers.exs lib/app/providers/provider.ex
git commit -m "feat: add Provider schema with encrypted api_key"
```

---

## Task 4: Create Providers Context

**Files:**
- Create: `lib/app/providers.ex`

**Step 1: Create Providers context**

Create `lib/app/providers.ex`:
```elixir
defmodule App.Providers do
  @moduledoc """
  The Providers context for managing user LLM providers.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Providers.Provider
  alias App.Users.Scope

  def list_providers(%Scope{} = scope) do
    Repo.all(from p in Provider, where: p.user_id == ^scope.user.id)
  end

  def get_provider!(%Scope{} = scope, id) do
    Repo.get_by!(Provider, id: id, user_id: scope.user.id)
  end

  def get_provider(%Scope{} = scope, id) do
    Repo.get_by(Provider, id: id, user_id: scope.user.id)
  end

  def create_provider(%Scope{} = scope, attrs) do
    attrs = Map.put(attrs, "user_id", scope.user.id)

    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
  end

  def update_provider(%Scope{} = scope, %Provider{} = provider, attrs) do
    ensure_user_owns_provider!(scope, provider)

    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
  end

  def delete_provider(%Scope{} = scope, %Provider{} = provider) do
    ensure_user_owns_provider!(scope, provider)

    Repo.delete(provider)
  end

  def change_provider(%Provider{} = provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  defp ensure_user_owns_provider!(%Scope{} = scope, %Provider{} = provider) do
    if provider.user_id != scope.user.id do
      raise Ecto.NoResultsError, query: Provider
    end
  end
end
```

**Step 2: Commit context**

```bash
git add lib/app/providers.ex
git commit -m "feat: add Providers context with CRUD operations"
```

---

## Task 5: Create Provider LiveView Index

**Files:**
- Create: `lib/app_web/live/provider_live/index.ex`
- Create: `lib/app_web/live/provider_live/index.html.heex`

**Step 1: Create ProviderLive.Index**

Create `lib/app_web/live/provider_live/index.ex`:
```elixir
defmodule AppWeb.ProviderLive.Index do
  use AppWeb, :live_view

  alias App.Providers
  alias App.Providers.Provider

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :providers, Providers.list_providers(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Providers")
    |> assign(:provider, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Provider")
    |> assign(:provider, %Provider{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    provider = Providers.get_provider!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Provider")
    |> assign(:provider, provider)
  end

  @impl true
  def handle_info({AppWeb.ProviderLive.FormComponent, {:saved, provider}}, socket) do
    {:noreply, stream_insert(socket, :providers, provider)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    provider = Providers.get_provider!(socket.assigns.current_scope, id)
    {:ok, _} = Providers.delete_provider(socket.assigns.current_scope, provider)

    {:noreply, stream_delete(socket, :providers, provider)}
  end
end
```

**Step 2: Create index template**

Create `lib/app_web/live/provider_live/index.html.heex`:
```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <.header>
    Providers
    <:actions>
      <.link navigate={~p"/providers/new"}>
        <.button>New Provider</.button>
      </.link>
    </:actions>
  </.header>

  <div id="providers" phx-update="stream" class="mt-6">
    <div :for={{id, provider} <- @streams.providers} id={id} class="flex items-center justify-between p-4 border-b">
      <div>
        <p class="font-medium">{provider.name || provider.provider}</p>
        <p class="text-sm text-gray-500">{provider.provider}</p>
      </div>
      <div class="flex gap-2">
        <.link navigate={~p"/providers/#{provider.id}/edit"}>
          <.button variant="outline">Edit</.button>
        </.link>
        <.button phx-click="delete" phx-value-id={provider.id} data-confirm="Are you sure?">
          Delete
        </.button>
      </div>
    </div>
    <div class="hidden only:block p-4 text-center text-gray-500">
      No providers configured yet.
    </div>
  </div>
</Layouts.app>
```

**Step 3: Commit index LiveView**

```bash
git add lib/app_web/live/provider_live/
git commit -m "feat: add Provider LiveView index"
```

---

## Task 6: Create Provider Form Component

**Files:**
- Create: `lib/app_web/live/provider_live/form_component.ex`
- Create: `lib/app_web/live/provider_live/form_component.html.heex`

**Step 1: Create FormComponent**

Create `lib/app_web/live/provider_live/form_component.ex`:
```elixir
defmodule AppWeb.ProviderLive.FormComponent do
  use AppWeb, :live_component

  alias App.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.form for={@form} id="provider-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Name (optional)" />

        <.input
          field={@form[:provider]}
          type="select"
          label="Provider"
          options={[
            {"OpenAI", "openai"},
            {"Anthropic", "anthropic"},
            {"Google", "google"},
            {"Gemini", "gemini"},
            {"Mistral", "mistral"},
            {"Cohere", "cohere"}
          ]}
          prompt="Select a provider"
        />

        <.input field={@form[:api_key]} type="password" label="API Key" />

        <:actions>
          <.button>Save Provider</.button>
        </:actions>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{provider: provider} = assigns, socket) do
    changeset = Providers.change_provider(provider)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"provider" => provider_params}, socket) do
    changeset =
      socket.assigns.provider
      |> Providers.change_provider(provider_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"provider" => provider_params}, socket) do
    save_provider(socket, socket.assigns.action, provider_params)
  end

  defp save_provider(socket, :edit, provider_params) do
    case Providers.update_provider(socket.assigns.current_scope, socket.assigns.provider, provider_params) do
      {:ok, provider} ->
        notify_parent({:saved, provider})

        {:noreply,
         socket
         |> put_flash(:info, "Provider updated successfully")
         |> push_patch(to: ~p"/providers")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_provider(socket, :new, provider_params) do
    case Providers.create_provider(socket.assigns.current_scope, provider_params) do
      {:ok, provider} ->
        notify_parent({:saved, provider})

        {:noreply,
         socket
         |> put_flash(:info, "Provider created successfully")
         |> push_patch(to: ~p"/providers")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
```

**Step 2: Commit form component**

```bash
git add lib/app_web/live/provider_live/form_component.ex
git commit -m "feat: add Provider form component"
```

---

## Task 7: Add Routes and Navigation

**Files:**
- Modify: `lib/app_web/router.ex:50-61`
- Modify: `lib/app_web/components/layouts.ex`

**Step 1: Add provider routes**

Modify `lib/app_web/router.ex`, add inside `live_session :require_authenticated_user`:
```elixir
live "/providers", ProviderLive.Index, :index
live "/providers/new", ProviderLive.Index, :new
live "/providers/:id/edit", ProviderLive.Index, :edit
```

**Step 2: Commit routes**

```bash
git add lib/app_web/router.ex
git commit -m "feat: add provider routes"
```

---

## Task 8: Write Tests

**Files:**
- Create: `test/app/providers_test.exs`
- Create: `test/support/fixtures/providers_fixtures.ex`

**Step 1: Create providers fixtures**

Create `test/support/fixtures/providers_fixtures.ex`:
```elixir
defmodule App.ProvidersFixtures do
  alias App.Users.Scope

  def provider_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "My OpenAI",
      provider: "openai",
      api_key: "sk-test-123456"
    })
  end

  def provider_fixture(user, attrs \\ %{}) do
    scope = %Scope{user: user}

    {:ok, provider} =
      App.Providers.create_provider(scope, provider_attrs(attrs))

    provider
  end
end
```

**Step 2: Create providers test**

Create `test/app/providers_test.exs`:
```elixir
defmodule App.ProvidersTest do
  use App.DataCase

  alias App.Providers
  alias App.UsersFixtures
  alias App.Users.Scope

  setup do
    user = UsersFixtures.user_fixture()
    scope = %Scope{user: user}
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

    test "returns error with invalid provider", %{scope: scope} do
      attrs = %{
        "name" => "Test",
        "provider" => "invalid",
        "api_key" => "key"
      }

      assert {:error, changeset} = Providers.create_provider(scope, attrs)
      assert "is invalid" in errors_on(changeset).provider
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
      Providers.create_provider(%Scope{user: user}, Map.merge(%{
        "provider" => "openai",
        "api_key" => "test-key"
      }, attrs))

    provider
  end
end
```

**Step 3: Run tests**

Run: `mix test test/app/providers_test.exs`
Expected: All tests pass

**Step 4: Commit tests**

```bash
git add test/app/providers_test.exs test/support/fixtures/providers_fixtures.ex
git commit -m "test: add providers context tests"
```

---

## Task 9: Final Verification

**Step 1: Run all tests**

Run: `mix test`
Expected: All tests pass

**Step 2: Run precommit**

Run: `mix precommit`
Expected: All checks pass

**Step 3: Verify server starts**

Run: `mix phx.server`
Expected: Server starts without errors

**Step 4: Test in browser**

Navigate to `/providers` after logging in and verify:
- Provider list displays
- Can create new provider
- Provider API key is encrypted in database
