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

  @known_provider_types Provider.provider_types()

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
    @known_provider_types
    |> Enum.sort()
    |> Enum.map(fn type ->
      {type, humanize_provider_type(type)}
    end)
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

  defp humanize_provider_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
