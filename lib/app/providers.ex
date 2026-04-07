defmodule App.Providers do
  @moduledoc """
  The Providers context for managing user LLM providers.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Providers.Provider
  alias App.Users.Scope
  alias LLMDB
  alias ReqLLM.Provider.Generated.ValidProviders

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
    %Provider{user_id: scope.user.id}
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

  defp ensure_user_owns_provider!(%Scope{} = scope, provider) do
    if provider.user_id != scope.user.id do
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
