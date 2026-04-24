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
    normalized =
      attrs
      |> stringify_map()
      |> normalize_memory_attrs()

    case find_existing_memory(normalized) do
      %Memory{} = existing ->
        existing |> Memory.changeset(normalized) |> Repo.update()

      nil ->
        %Memory{} |> Memory.changeset(normalized) |> Repo.insert()
    end
  end

  def get_memory(scope, key, opts \\ [])

  def get_memory(scope, key, opts) when is_list(opts) do
    scope = normalize_optional_text(scope)
    key = normalize_optional_text(key)

    cond do
      is_nil(scope) or is_nil(key) ->
        nil

      true ->
        Memory
        |> where([m], m.key == ^key)
        |> maybe_filter_memory_scope(scope, opts)
        |> Repo.one()
    end
  end

  def get_memories_by_tags(tags, opts \\ []) when is_list(tags) do
    tags = normalize_tags(tags)

    if tags == [] do
      []
    else
      accessible_memories_query(opts)
      |> where([m], fragment("? && ?::varchar[]", m.tags, ^tags))
      |> order_by([m], desc: m.updated_at)
      |> Repo.all()
    end
  end

  def list_memories(opts \\ []) when is_list(opts) do
    scope = normalize_optional_text(Keyword.get(opts, :scope))
    tags = normalize_tags(Keyword.get(opts, :tags, []))
    limit = normalize_memory_limit(Keyword.get(opts, :limit, 50))

    accessible_memories_query(opts)
    |> maybe_filter_memory_scope(scope, opts)
    |> maybe_filter_memory_tags(tags)
    |> order_by([m], desc: m.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_memories_for_prompt(agent_id, opts \\ []) do
    tags = ~w(preferences preference profile)

    case {normalize_optional_text(agent_id),
          normalize_optional_text(Keyword.get(opts, :organization_id))} do
      {nil, _} ->
        []

      {_, nil} ->
        []

      {agent_id, organization_id} ->
        Memory
        |> where(
          [m],
          m.organization_id == ^organization_id and m.agent_id == ^agent_id and is_nil(m.user_id)
        )
        |> where([m], fragment("? && ?::varchar[]", m.tags, ^tags))
        |> order_by([m], asc: m.inserted_at)
        |> Repo.all()
    end
  end

  def list_user_profile_memories_for_prompt(opts \\ []) when is_list(opts) do
    organization_id = normalize_optional_text(Keyword.get(opts, :organization_id))
    user_id = normalize_optional_text(Keyword.get(opts, :user_id))

    if is_binary(organization_id) and organization_id != "" and is_binary(user_id) and
         user_id != "" do
      Memory
      |> where(
        [m],
        m.organization_id == ^organization_id and m.user_id == ^user_id and is_nil(m.agent_id)
      )
      |> where([m], fragment("? && ?::varchar[]", m.tags, ^~w(preferences preference profile)))
      |> order_by([m], asc: m.inserted_at)
      |> Repo.all()
    else
      []
    end
  end

  def list_org_memory_keys_for_prompt(opts \\ []) when is_list(opts) do
    organization_id = normalize_optional_text(Keyword.get(opts, :organization_id))
    limit = normalize_memory_limit(Keyword.get(opts, :limit, 30))

    if is_binary(organization_id) and organization_id != "" do
      Memory
      |> where(
        [m],
        m.organization_id == ^organization_id and is_nil(m.user_id) and is_nil(m.agent_id)
      )
      |> order_by([m], asc: m.inserted_at)
      |> limit(^limit)
      |> select([m], %{key: m.key, tags: m.tags})
      |> Repo.all()
    else
      []
    end
  end

  def search_memories(query, opts \\ []) when is_binary(query) do
    case normalize_optional_text(query) do
      nil ->
        []

      trimmed_query ->
        pattern = "%#{trimmed_query}%"

        accessible_memories_query(opts)
        |> where([m], ilike(m.key, ^pattern) or ilike(m.value, ^pattern))
        |> order_by([m], desc: m.updated_at)
        |> limit(20)
        |> Repo.all()
    end
  end

  def delete_memory(%Memory{} = memory), do: Repo.delete(memory)

  defp find_existing_memory(attrs) do
    organization_id = normalize_optional_text(Map.get(attrs, "organization_id"))
    key = normalize_optional_text(Map.get(attrs, "key"))
    user_id = normalize_optional_text(Map.get(attrs, "user_id"))
    agent_id = normalize_optional_text(Map.get(attrs, "agent_id"))

    if is_nil(organization_id) or is_nil(key) do
      nil
    else
      Memory
      |> where([m], m.organization_id == ^organization_id and m.key == ^key)
      |> maybe_owner_filter(user_id, agent_id)
      |> Repo.one()
    end
  end

  defp maybe_owner_filter(query, nil, nil),
    do: where(query, [m], is_nil(m.user_id) and is_nil(m.agent_id))

  defp maybe_owner_filter(query, user_id, nil),
    do: where(query, [m], m.user_id == ^user_id and is_nil(m.agent_id))

  defp maybe_owner_filter(query, nil, agent_id),
    do: where(query, [m], m.agent_id == ^agent_id and is_nil(m.user_id))

  defp maybe_owner_filter(query, _user_id, _agent_id), do: where(query, [m], false)

  defp accessible_memories_query(opts) do
    organization_id = Keyword.get(opts, :organization_id)

    if is_binary(organization_id) and organization_id != "" do
      Memory
      |> where([m], m.organization_id == ^organization_id)
      |> where(^accessible_memory_dynamic(opts))
    else
      where(Memory, [m], false)
    end
  end

  defp accessible_memory_dynamic(opts) do
    user_id = Keyword.get(opts, :user_id)
    agent_id = Keyword.get(opts, :agent_id)

    dynamic =
      dynamic([m], is_nil(m.user_id) and is_nil(m.agent_id))

    dynamic =
      if is_binary(user_id) and user_id != "" do
        dynamic(
          [m],
          ^dynamic or (m.user_id == ^user_id and is_nil(m.agent_id))
        )
      else
        dynamic
      end

    if is_binary(agent_id) and agent_id != "" do
      dynamic(
        [m],
        ^dynamic or (m.agent_id == ^agent_id and is_nil(m.user_id))
      )
    else
      dynamic
    end
  end

  defp maybe_filter_memory_scope(query, scope, opts) do
    if is_nil(scope) do
      query
    else
      do_maybe_filter_memory_scope(query, scope, opts)
    end
  end

  defp do_maybe_filter_memory_scope(query, scope, opts) do
    organization_id = Keyword.get(opts, :organization_id)

    if is_binary(organization_id) and organization_id != "" do
      base_query = where(query, [m], m.organization_id == ^organization_id)

      case scope do
        "org" ->
          where(base_query, [m], is_nil(m.user_id) and is_nil(m.agent_id))

        "user" ->
          user_id = Keyword.get(opts, :user_id)

          if is_binary(user_id) and user_id != "" do
            where(base_query, [m], m.user_id == ^user_id and is_nil(m.agent_id))
          else
            where(base_query, [m], false)
          end

        "agent" ->
          agent_id = Keyword.get(opts, :agent_id)

          if is_binary(agent_id) and agent_id != "" do
            where(base_query, [m], m.agent_id == ^agent_id and is_nil(m.user_id))
          else
            where(base_query, [m], false)
          end

        _other ->
          where(base_query, [m], false)
      end
    else
      where(query, [m], false)
    end
  end

  defp maybe_filter_memory_tags(query, []), do: query

  defp maybe_filter_memory_tags(query, tags) do
    where(query, [m], fragment("? && ?::varchar[]", m.tags, ^tags))
  end

  defp normalize_memory_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, 200)
  defp normalize_memory_limit(_limit), do: 50

  defp normalize_memory_attrs(attrs) do
    scope = normalize_optional_text(Map.get(attrs, "scope")) || "org"

    attrs =
      attrs
      |> maybe_put_trimmed("key")
      |> maybe_put_trimmed("value")
      |> maybe_put_trimmed("organization_id")
      |> maybe_put_trimmed("user_id")
      |> maybe_put_trimmed("agent_id")
      |> Map.delete("scope")

    case scope do
      "org" ->
        attrs
        |> Map.put("agent_id", nil)
        |> Map.put("user_id", nil)

      "user" ->
        Map.put(attrs, "agent_id", nil)

      "agent" ->
        Map.put(attrs, "user_id", nil)

      _other ->
        attrs
    end
  end

  defp maybe_put_trimmed(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, normalize_optional_text(value))
      :error -> attrs
    end
  end

  defp normalize_tags(tags) do
    tags
    |> List.wrap()
    |> Enum.map(&normalize_optional_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(value), do: value

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
