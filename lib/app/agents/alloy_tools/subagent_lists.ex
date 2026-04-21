defmodule App.Agents.AlloyTools.SubagentLists do
  @moduledoc """
  Alloy tool for listing the other assigned agents in the current room with their
  instructions and available tools.
  """
  @behaviour Alloy.Tool

  alias App.Agents.Agent
  alias App.Agents.Tools, as: AgentTools
  alias App.Tools
  alias App.Tools.Tool

  @impl true
  def name, do: "subagent_lists"

  @impl true
  def description do
    "List the other assigned agents in this room, including their instructions and available tools."
  end

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{},
      required: []
    }
  end

  @impl true
  def execute(_input, context) do
    with {:ok, agents} <- room_agents(context),
         {:ok, current_agent_id} <- current_agent_id(context),
         {:ok, organization_id} <- organization_id(agents, context) do
      other_agents =
        agents
        |> Enum.reject(&(&1.id == current_agent_id))
        |> Enum.map(&serialize_agent(&1, organization_id))

      {:ok, Jason.encode!(%{"agents" => other_agents})}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp room_agents(%{agents: agents}) when is_list(agents) and agents != [] do
    {:ok, Enum.filter(agents, &match?(%Agent{}, &1))}
  end

  defp room_agents(%{agent_map: agent_map}) when is_map(agent_map) and map_size(agent_map) > 0 do
    {:ok, Map.values(agent_map)}
  end

  defp room_agents(_context), do: {:error, "sub-agent listing requires assigned agents"}

  defp current_agent_id(%{current_agent_id: current_agent_id}) when is_binary(current_agent_id),
    do: {:ok, current_agent_id}

  defp current_agent_id(%{chat_room: %{chat_room_agents: chat_room_agents}})
       when is_list(chat_room_agents) do
    case Enum.find(chat_room_agents, & &1.is_active) || List.first(chat_room_agents) do
      %{agent_id: agent_id} when is_binary(agent_id) -> {:ok, agent_id}
      %{agent: %Agent{id: agent_id}} when is_binary(agent_id) -> {:ok, agent_id}
      _other -> {:error, "sub-agent listing requires an active agent"}
    end
  end

  defp current_agent_id(_context), do: {:error, "sub-agent listing requires an active agent"}

  defp organization_id([%Agent{organization_id: organization_id} | _rest], _context)
       when is_binary(organization_id),
       do: {:ok, organization_id}

  defp organization_id(_agents, %{chat_room: %{organization_id: organization_id}})
       when is_binary(organization_id),
       do: {:ok, organization_id}

  defp organization_id(_agents, _context),
    do: {:error, "sub-agent listing requires an organization context"}

  defp serialize_agent(%Agent{} = agent, organization_id) do
    %{
      "agent_id" => agent.id,
      "name" => agent.name,
      "instructions" => agent.system_prompt,
      "tools" => resolve_tool_details(agent.tools || [], organization_id)
    }
  end

  defp resolve_tool_details(tool_names, organization_id) do
    builtin_tools = AgentTools.listable_builtin_tools()
    builtin_by_name = Map.new(builtin_tools, &{&1.name, &1.description})

    custom_by_name =
      tool_names
      |> Enum.reject(&Map.has_key?(builtin_by_name, &1))
      |> then(&Tools.list_named_tools(organization_id, &1))
      |> Map.new(fn %Tool{name: name, description: description} -> {name, description} end)

    Enum.map(tool_names, fn tool_name ->
      %{
        "name" => tool_name,
        "description" => Map.get(builtin_by_name, tool_name) || Map.get(custom_by_name, tool_name)
      }
    end)
  end
end
