defmodule AppWeb.AgentLive.New do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Agents.Agent
  alias App.Providers
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    if Scope.manager?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(:can_manage_organization?, true)
       |> assign(:providers, Providers.list_providers(socket.assigns.current_scope))
       |> assign(:available_tools, Agents.available_tools(socket.assigns.current_scope))}
    else
      {:ok,
       socket
       |> assign(:can_manage_organization?, false)
       |> assign(:page_title, "Agents")
       |> assign(:agent, %Agent{})
       |> assign(:providers, [])
       |> assign(:available_tools, [])
       |> put_flash(:error, "Only organization owners and admins can manage agents.")
       |> push_navigate(to: ~p"/agents")}
    end
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{can_manage_organization?: true}} = socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({AppWeb.AgentLive.FormComponent, {:saved, _agent}}, socket) do
    {:noreply, socket}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Create Agent")
    |> assign(:agent, %Agent{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    cond do
      not socket.assigns.can_manage_organization? ->
        socket
        |> put_flash(:error, "Only organization owners and admins can manage agents.")
        |> push_navigate(to: ~p"/agents")

      agent = Agents.get_agent(socket.assigns.current_scope, id) ->
        socket
        |> assign(:page_title, "Edit Agent")
        |> assign(:agent, agent)

      agent = Agents.get_agent_for_user(socket.assigns.current_scope.user, id) ->
        redirect(
          socket,
          to: switch_path(agent.organization_id, ~p"/agents/#{id}/edit")
        )

      true ->
        raise Ecto.NoResultsError, query: Agent
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      sidebar_chat_rooms={@sidebar_chat_rooms}
      sidebar_organizations={@sidebar_organizations}
    >
      <div class="flex h-full min-h-0 flex-col p-4 pt-20 sm:px-5 sm:pb-5 sm:pt-20 lg:p-6">
        <div id={agent_page_id(@live_action)} class="mx-auto w-full max-w-4xl">
          <section class="space-y-6">
            <div class="space-y-3 border-b border-border pb-6">
              <.link
                navigate={~p"/agents"}
                class="inline-flex w-fit items-center gap-2 text-sm text-muted-foreground transition hover:text-foreground"
              >
                <.icon name="hero-arrow-left" class="size-4" />
                <span>Back to agents</span>
              </.link>

              <div class="space-y-2">
                <h1 class="text-3xl font-bold tracking-tight text-foreground">{@page_title}</h1>
                <p class="text-sm text-muted-foreground">
                  Build a reusable assistant tied to one provider, one model, and the tools you want it to use.
                </p>
              </div>
            </div>

            <.live_component
              module={AppWeb.AgentLive.FormComponent}
              id={agent_form_component_id(@live_action, @agent)}
              title={@page_title}
              action={@live_action}
              agent={@agent}
              providers={@providers}
              available_tools={@available_tools}
              current_scope={@current_scope}
              display_mode={:page}
              navigation={:navigate}
              return_to={~p"/agents"}
            />
          </section>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end

  defp agent_page_id(:edit), do: "agent-edit-page"
  defp agent_page_id(_action), do: "agent-create-page"

  defp agent_form_component_id(:edit, %Agent{id: id}), do: id
  defp agent_form_component_id(_action, _agent), do: "new-agent"

  defp switch_path(organization_id, return_to) do
    ~p"/organizations/switch/#{organization_id}?return_to=#{return_to}"
  end
end
