defmodule AppWeb.AgentLive.Index do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Agents.Agent
  alias App.Providers
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    providers = Providers.list_providers(socket.assigns.current_scope)
    agents = Agents.list_agents(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:providers, providers)
     |> assign(:can_manage_organization?, Scope.manager?(socket.assigns.current_scope))
     |> assign(:available_tools, Agents.available_tools(socket.assigns.current_scope))
     |> stream_configure(:agents, dom_id: &"agent-#{&1.id}")
     |> stream(:agents, agents)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Agents")
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if socket.assigns.can_manage_organization? do
      agent = Agents.get_agent!(socket.assigns.current_scope, id)
      {:ok, _agent} = Agents.delete_agent(socket.assigns.current_scope, agent)

      {:noreply, stream_delete(socket, :agents, agent)}
    else
      {:noreply,
       put_flash(socket, :error, "Only organization owners and admins can manage agents.")}
    end
  end

  def provider_label(%Agent{provider: provider}) do
    provider.name || String.capitalize(provider.provider)
  end

  def model_name(%Agent{model: model}) do
    case String.split(model, ":", parts: 2) do
      [_provider, model_name] -> model_name
      [model_name] -> model_name
    end
  end

  def tool_count(%Agent{tools: tools}), do: length(tools)

  def tool_count_label(%Agent{} = agent) do
    case tool_count(agent) do
      1 -> "1 tool"
      count -> "#{count} tools"
    end
  end
end
