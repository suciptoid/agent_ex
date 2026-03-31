defmodule AppWeb.AgentLive.Index do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Agents.Agent
  alias App.Providers

  @impl true
  def mount(_params, _session, socket) do
    providers = Providers.list_providers(socket.assigns.current_scope)
    agents = Agents.list_agents(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:providers, providers)
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
    |> assign(:agent, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Agent")
    |> assign(:agent, %Agent{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    agent = Agents.get_agent!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Agent")
    |> assign(:agent, agent)
  end

  @impl true
  def handle_info({AppWeb.AgentLive.FormComponent, {:saved, agent}}, socket) do
    {:noreply, stream_insert(socket, :agents, agent)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    agent = Agents.get_agent!(socket.assigns.current_scope, id)
    {:ok, _agent} = Agents.delete_agent(socket.assigns.current_scope, agent)

    {:noreply, stream_delete(socket, :agents, agent)}
  end

  def provider_label(%Agent{provider: provider}) do
    provider.name || String.capitalize(provider.provider)
  end

  def tools_summary(%Agent{tools: []}), do: "No tools enabled"
  def tools_summary(%Agent{tools: tools}), do: Enum.join(tools, ", ")
end
