defmodule App.Providers do
  @moduledoc """
  The Providers context for managing user LLM providers.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Organizations.Membership
  alias App.Providers.Provider
  alias App.Users.Scope
  alias App.Users.User
  alias LLMDB
  alias ReqLLM.Provider.Generated.ValidProviders

  def list_providers(%Scope{} = scope) do
    Repo.all(
      from provider in Provider,
        where: provider.organization_id == ^Scope.organization_id!(scope),
        order_by: [asc: provider.name, asc: provider.inserted_at]
    )
  end

  def count_providers(%Scope{} = scope) do
    Repo.aggregate(
      from(provider in Provider,
        where: provider.organization_id == ^Scope.organization_id!(scope)
      ),
      :count,
      :id
    )
  end

  def get_provider!(%Scope{} = scope, id) do
    Repo.get_by!(Provider, id: id, organization_id: Scope.organization_id!(scope))
  end

  def get_provider(%Scope{} = scope, id) do
    Repo.get_by(Provider, id: id, organization_id: Scope.organization_id!(scope))
  end

  def get_provider_for_user(%User{} = user, id) do
    Provider
    |> join(:inner, [provider], membership in Membership,
      on: membership.organization_id == provider.organization_id
    )
    |> where([provider, membership], membership.user_id == ^user.id and provider.id == ^id)
    |> select([provider, _membership], provider)
    |> Repo.one()
  end

  def create_provider(%Scope{} = scope, attrs) do
    with :ok <- authorize_manager(scope) do
      %Provider{organization_id: Scope.organization_id!(scope)}
      |> Provider.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_provider(%Scope{} = scope, provider, attrs) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_provider(scope, provider) do
      provider
      |> Provider.changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_provider(%Scope{} = scope, provider) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_provider(scope, provider) do
      Repo.delete(provider)
    end
  end

  def change_provider(provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  def provider_options do
    provider_name_map = provider_name_map()

    valid_provider_ids()
    |> Enum.sort_by(&provider_label(&1, provider_name_map))
    |> Enum.map(fn provider_id ->
      {Atom.to_string(provider_id), provider_label(provider_id, provider_name_map)}
    end)
  end

  def valid_provider_ids do
    (ValidProviders.list() ++ Enum.map(LLMDB.providers(), & &1.id))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def valid_provider_values do
    valid_provider_ids()
    |> Enum.map(&Atom.to_string/1)
  end

  defp authorize_manager(%Scope{} = scope) do
    if Scope.manager?(scope), do: :ok, else: {:error, :forbidden}
  end

  defp ensure_organization_owns_provider(%Scope{} = scope, provider) do
    if provider.organization_id == Scope.organization_id!(scope) do
      :ok
    else
      raise Ecto.NoResultsError, query: Provider
    end
  end

  defp provider_name_map do
    LLMDB.providers()
    |> Map.new(fn provider -> {provider.id, provider.name} end)
  end

  defp provider_label(provider_id, provider_name_map) do
    Map.get(provider_name_map, provider_id) || humanize_provider_id(provider_id)
  end

  defp humanize_provider_id(provider_id) do
    provider_id
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
