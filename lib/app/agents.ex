defmodule App.Agents do
  @moduledoc """
  The Agents context.
  """

  import Ecto.Query, warn: false

  alias App.Agents.Agent
  alias App.Agents.Memory
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

  # ── Memory ──

  def set_memory(attrs) when is_map(attrs) do
    normalized = stringify_map(attrs)
    scope = Map.get(normalized, "scope", "org")

    merged_attrs = Map.put(normalized, "scope", scope)

    case find_existing_memory(merged_attrs) do
      %Memory{} = existing ->
        existing
        |> Memory.changeset(merged_attrs)
        |> Repo.update()

      nil ->
        %Memory{}
        |> Memory.changeset(merged_attrs)
        |> Repo.insert()
    end
  end

  def get_memory(scope, agent_id, key, opts \\ []) do
    Memory
    |> where([m], m.agent_id == ^agent_id and m.key == ^key and m.scope == ^scope)
    |> apply_scope_filter(opts)
    |> Repo.one()
  end

  def get_memories_by_tags(agent_id, tags, opts \\ []) when is_list(tags) do
    Memory
    |> where([m], m.agent_id == ^agent_id)
    |> apply_scope_filter(opts)
    |> where([m], fragment("? && ?::varchar[]", m.tags, ^tags))
    |> order_by([m], desc: m.updated_at)
    |> Repo.all()
  end

  def list_memories_for_prompt(agent_id, opts \\ []) do
    tags = ~w(preferences preference profile)

    Memory
    |> where([m], m.agent_id == ^agent_id)
    |> apply_scope_filter(opts)
    |> where([m], fragment("? && ?::varchar[]", m.tags, ^tags))
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  def search_memories(agent_id, query, opts \\ []) when is_binary(query) do
    pattern = "%#{query}%"

    Memory
    |> where([m], m.agent_id == ^agent_id)
    |> apply_scope_filter(opts)
    |> where([m], ilike(m.key, ^pattern) or ilike(m.value, ^pattern))
    |> order_by([m], desc: m.updated_at)
    |> limit(20)
    |> Repo.all()
  end

  def delete_memory(%Memory{} = memory), do: Repo.delete(memory)

  defp find_existing_memory(attrs) do
    agent_id = Map.get(attrs, "agent_id")
    key = Map.get(attrs, "key")
    scope = Map.get(attrs, "scope", "org")
    user_id = Map.get(attrs, "user_id")

    if is_nil(agent_id) or is_nil(key) do
      nil
    else
      Memory
      |> where([m], m.agent_id == ^agent_id and m.key == ^key and m.scope == ^scope)
      |> maybe_where_user_id(user_id)
      |> Repo.one()
    end
  end

  defp maybe_where_user_id(query, nil), do: where(query, [m], is_nil(m.user_id))
  defp maybe_where_user_id(query, user_id), do: where(query, [m], m.user_id == ^user_id)

  defp apply_scope_filter(query, opts) do
    query
    |> maybe_filter_scope(opts)
  end

  defp maybe_filter_scope(query, opts) do
    scope = Keyword.get(opts, :scope)
    user_id = Keyword.get(opts, :user_id)

    query
    |> maybe_scope_where(scope)
    |> maybe_user_where(user_id)
  end

  defp maybe_scope_where(query, nil), do: query
  defp maybe_scope_where(query, scope), do: where(query, [m], m.scope == ^scope)

  defp maybe_user_where(query, nil), do: query
  defp maybe_user_where(query, user_id), do: where(query, [m], m.user_id == ^user_id)

  defp stringify_map(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

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
        thinking_mode: thinking_mode_from_extra_params(extra_params)
    }
  end

  defp thinking_mode_from_extra_params(extra_params) when is_map(extra_params) do
    cond do
      Map.get(extra_params, "thinking") == "enabled" ->
        "enabled"

      Map.get(extra_params, :thinking) == "enabled" ->
        "enabled"

      Map.get(extra_params, "reasoning_effort") in ["minimal", "low", "medium", "high", "xhigh"] ->
        "enabled"

      Map.get(extra_params, :reasoning_effort) in ["minimal", "low", "medium", "high", "xhigh"] ->
        "enabled"

      true ->
        "disabled"
    end
  end

  defp thinking_mode_from_extra_params(_extra_params), do: "disabled"
end
