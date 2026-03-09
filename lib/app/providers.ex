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

    struct(Provider, %{})
    |> Provider.changeset(attrs)
    |> Repo.insert()
  end

  def update_provider(%Scope{} = scope, provider, attrs) do
    ensure_user_owns_provider!(scope, provider)

    provider
    |> Provider.changeset(attrs)
    |> Repo.update()
  end

  def delete_provider(%Scope{} = scope, provider) do
    ensure_user_owns_provider!(scope, provider)

    Repo.delete(provider)
  end

  def change_provider(provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  defp ensure_user_owns_provider!(%Scope{} = scope, provider) do
    if provider.user_id != scope.user.id do
      raise Ecto.NoResultsError, query: Provider
    end
  end
end
