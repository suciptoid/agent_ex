defmodule App.Agents do
  @moduledoc """
  The Agents context.
  """

  import Ecto.Query, warn: false

  alias App.Agents.Agent
  alias App.Organizations.Membership
  alias App.Providers.Provider
  alias App.Repo
  alias App.Tools
  alias App.Users.Scope
  alias App.Users.User

  def list_agents(%Scope{} = scope) do
    Agent
    |> where([agent], agent.organization_id == ^Scope.organization_id!(scope))
    |> order_by([agent], desc: agent.inserted_at)
    |> preload([:provider])
    |> Repo.all()
  end

  def count_agents(%Scope{} = scope) do
    Repo.aggregate(
      from(agent in Agent, where: agent.organization_id == ^Scope.organization_id!(scope)),
      :count,
      :id
    )
  end

  def list_recent_agents(%Scope{} = scope, limit \\ 5) when is_integer(limit) and limit > 0 do
    Agent
    |> where([agent], agent.organization_id == ^Scope.organization_id!(scope))
    |> order_by([agent], desc: agent.inserted_at)
    |> limit(^limit)
    |> preload([:provider])
    |> Repo.all()
  end

  def get_agent!(%Scope{} = scope, id) do
    Agent
    |> where(
      [agent],
      agent.organization_id == ^Scope.organization_id!(scope) and agent.id == ^id
    )
    |> preload([:provider])
    |> Repo.one!()
  end

  def get_agent(%Scope{} = scope, id) do
    Agent
    |> where(
      [agent],
      agent.organization_id == ^Scope.organization_id!(scope) and agent.id == ^id
    )
    |> preload([:provider])
    |> Repo.one()
  end

  def get_agent_for_user(%User{} = user, id) do
    Agent
    |> join(:inner, [agent], membership in Membership,
      on: membership.organization_id == agent.organization_id
    )
    |> where([agent, membership], membership.user_id == ^user.id and agent.id == ^id)
    |> preload([:provider])
    |> select([agent, _membership], agent)
    |> Repo.one()
  end

  def create_agent(%Scope{} = scope, attrs) do
    with :ok <- authorize_manager(scope) do
      %Agent{organization_id: Scope.organization_id!(scope)}
      |> Agent.changeset(attrs, allowed_tools: available_tools(scope))
      |> validate_provider_ownership(scope)
      |> Repo.insert()
      |> preload_agent()
    end
  end

  def update_agent(%Scope{} = scope, %Agent{} = agent, attrs) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_agent(scope, agent) do
      agent
      |> Agent.changeset(attrs, allowed_tools: available_tools(scope))
      |> validate_provider_ownership(scope)
      |> Repo.update()
      |> preload_agent()
    end
  end

  def delete_agent(%Scope{} = scope, %Agent{} = agent) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_agent(scope, agent) do
      Repo.delete(agent)
    end
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
               where:
                 provider.id == ^provider_id and
                   provider.organization_id == ^Scope.organization_id!(scope)
           ) do
          changeset
        else
          Ecto.Changeset.add_error(
            changeset,
            :provider_id,
            "must belong to the current organization"
          )
        end
    end
  end

  defp authorize_manager(%Scope{} = scope) do
    if Scope.manager?(scope), do: :ok, else: {:error, :forbidden}
  end

  defp ensure_organization_owns_agent(%Scope{} = scope, %Agent{organization_id: organization_id}) do
    if organization_id == Scope.organization_id!(scope) do
      :ok
    else
      raise Ecto.NoResultsError, query: Agent
    end
  end

  defp prepare_agent_for_form(%Agent{} = agent) do
    extra_params = agent.extra_params || %{}

    %{
      agent
      | temperature: Map.get(extra_params, "temperature"),
        max_tokens: Map.get(extra_params, "max_tokens"),
        reasoning_effort: Map.get(extra_params, "reasoning_effort", "default")
    }
  end
end
