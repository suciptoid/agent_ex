defmodule AppWeb.AgentLive.New do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Agents.Agent
  alias App.Providers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create Agent")
     |> assign(:agent, %Agent{})
     |> assign(:providers, Providers.list_providers(socket.assigns.current_scope))
     |> assign(:available_tools, Agents.available_tools(socket.assigns.current_scope))}
  end

  @impl true
  def handle_info({AppWeb.AgentLive.FormComponent, {:saved, _agent}}, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      sidebar_chat_rooms={@sidebar_chat_rooms}
    >
      <div class="flex h-full min-h-0 flex-col p-4 pt-20 sm:px-5 sm:pb-5 sm:pt-20 lg:p-6">
        <div id="agent-create-page" class="mx-auto w-full max-w-4xl">
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
              id="new-agent"
              title={@page_title}
              action={:new}
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
end
