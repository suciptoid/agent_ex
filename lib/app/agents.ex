defmodule App.Agents do
  @moduledoc """
  The Agents context.
  """

  import Ecto.Query, warn: false

  alias App.Agents.Agent
  alias App.Providers.Provider
  alias App.Repo
  alias App.Tools
  alias App.Users.Scope

  def list_agents(%Scope{} = scope) do
    Agent
    |> where([agent], agent.user_id == ^scope.user.id)
    |> order_by([agent], desc: agent.inserted_at)
    |> preload([:provider])
    |> Repo.all()
  end

  def count_agents(%Scope{} = scope) do
    Repo.aggregate(from(agent in Agent, where: agent.user_id == ^scope.user.id), :count, :id)
  end

  def list_recent_agents(%Scope{} = scope, limit \\ 5) when is_integer(limit) and limit > 0 do
    Agent
    |> where([agent], agent.user_id == ^scope.user.id)
    |> order_by([agent], desc: agent.inserted_at)
    |> limit(^limit)
    |> preload([:provider])
    |> Repo.all()
  end

  def get_agent!(%Scope{} = scope, id) do
    Agent
    |> where([agent], agent.user_id == ^scope.user.id and agent.id == ^id)
    |> preload([:provider])
    |> Repo.one!()
  end

  def create_agent(%Scope{} = scope, attrs) do
    %Agent{user_id: scope.user.id}
    |> Agent.changeset(attrs, allowed_tools: available_tools(scope))
    |> validate_provider_ownership(scope)
    |> Repo.insert()
    |> preload_agent()
  end

  def update_agent(%Scope{} = scope, %Agent{} = agent, attrs) do
    ensure_user_owns_agent!(scope, agent)

    agent
    |> Agent.changeset(attrs, allowed_tools: available_tools(scope))
    |> validate_provider_ownership(scope)
    |> Repo.update()
    |> preload_agent()
  end

  def delete_agent(%Scope{} = scope, %Agent{} = agent) do
    ensure_user_owns_agent!(scope, agent)
    Repo.delete(agent)
  end

  def change_agent(%Scope{} = scope, %Agent{} = agent, attrs \\ %{}) do
    agent
    |> prepare_agent_for_form()
    |> Agent.changeset(attrs, allowed_tools: available_tools(scope))
  end

  def available_tools, do: App.Agents.Tools.available_tools()
  def available_tools(%Scope{} = scope), do: available_tools() ++ Tools.list_tool_names(scope)

  defp preload_agent({:ok, %Agent{} = agent}), do: {:ok, Repo.preload(agent, [:provider])}
  defp preload_agent({:error, _} = error), do: error

  defp validate_provider_ownership(changeset, %Scope{} = scope) do
    case Ecto.Changeset.get_field(changeset, :provider_id) do
      nil ->
        changeset

      provider_id ->
        if Repo.exists?(
             from provider in Provider,
               where: provider.id == ^provider_id and provider.user_id == ^scope.user.id
           ) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :provider_id, "must belong to the current user")
        end
    end
  end

  defp ensure_user_owns_agent!(%Scope{} = scope, %Agent{user_id: user_id}) do
    if user_id != scope.user.id do
      raise Ecto.NoResultsError, query: Agent
    end
  end

  defp prepare_agent_for_form(%Agent{} = agent) do
    extra_params = agent.extra_params || %{}

    %{
      agent
      | temperature: Map.get(extra_params, "temperature"),
        max_tokens: Map.get(extra_params, "max_tokens")
    }
  end
end
