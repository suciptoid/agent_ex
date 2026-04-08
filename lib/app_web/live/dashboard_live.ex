defmodule AppWeb.DashboardLive do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Chat
  alias App.Providers
  alias App.Tools
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    providers_count = Providers.count_providers(scope)
    agents_count = Agents.count_agents(scope)
    tools_count = Tools.count_tools(scope)
    conversations_count = Chat.count_chat_rooms(scope)
    can_manage_organization? = Scope.manager?(scope)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:can_manage_organization?, can_manage_organization?)
     |> assign(:organization_name, scope.organization.name)
     |> assign(:organization_role_label, organization_role_label(scope.organization_role))
     |> assign(:providers_count, providers_count)
     |> assign(:agents_count, agents_count)
     |> assign(:tools_count, tools_count)
     |> assign(:conversations_count, conversations_count)
     |> assign(:recent_agents, Agents.list_recent_agents(scope, 4))
     |> assign(:recent_chat_rooms, Chat.list_recent_chat_rooms(scope, 5))
     |> assign(
       :primary_action,
       primary_action(
         providers_count,
         agents_count,
         conversations_count,
         can_manage_organization?
       )
     )}
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
        <div class="space-y-6">
          <section class="overflow-hidden rounded-3xl border border-border bg-gradient-to-br from-card via-card to-primary/5 p-6 shadow-sm">
            <div class="flex flex-col gap-6 xl:flex-row xl:items-end xl:justify-between">
              <div class="space-y-4">
                <div
                  id="dashboard-status-pill"
                  class="inline-flex items-center gap-2 rounded-full border border-primary/15 bg-primary/5 px-3 py-1 text-xs font-medium text-primary"
                >
                  <.icon
                    name={
                      workspace_status_icon(@providers_count, @agents_count, @conversations_count)
                    }
                    class="size-3.5"
                  />
                  <span>
                    {workspace_status_label(@providers_count, @agents_count, @conversations_count)}
                  </span>
                </div>

                <div class="space-y-2">
                  <div class="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                    <span class="inline-flex items-center rounded-full border border-border bg-muted/60 px-2.5 py-1 font-medium text-foreground">
                      {@organization_name}
                    </span>
                    <span class="inline-flex items-center rounded-full border border-primary/20 bg-primary/10 px-2.5 py-1 font-medium text-primary">
                      {@organization_role_label}
                    </span>
                  </div>

                  <h1 id="dashboard-heading" class="text-3xl font-bold tracking-tight text-foreground">
                    Dashboard
                  </h1>
                  <p id="dashboard-summary" class="max-w-2xl text-sm leading-6 text-muted-foreground">
                    {hero_copy(
                      @organization_name,
                      @current_scope.user.email,
                      @providers_count,
                      @agents_count,
                      @conversations_count,
                      @can_manage_organization?
                    )}
                  </p>
                </div>
              </div>

              <.link
                :if={@primary_action}
                id="dashboard-primary-action"
                navigate={@primary_action.href}
              >
                <.button class="gap-2">
                  <.icon name={@primary_action.icon} class="size-4" />
                  {@primary_action.label}
                </.button>
              </.link>
            </div>
          </section>

          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <div
              id="dashboard-stat-providers"
              class="rounded-2xl border border-border bg-card p-5 shadow-sm"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="space-y-1">
                  <p class="text-sm font-medium text-muted-foreground">Providers</p>
                  <p
                    id="dashboard-stat-providers-value"
                    class="text-3xl font-semibold text-foreground"
                  >
                    {@providers_count}
                  </p>
                </div>
                <div class="flex size-11 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                  <.icon name="hero-server-stack" class="size-5" />
                </div>
              </div>
              <p class="mt-3 text-sm text-muted-foreground">
                Connected model vendors available to your agents.
              </p>
            </div>

            <div
              id="dashboard-stat-agents"
              class="rounded-2xl border border-border bg-card p-5 shadow-sm"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="space-y-1">
                  <p class="text-sm font-medium text-muted-foreground">Agents</p>
                  <p id="dashboard-stat-agents-value" class="text-3xl font-semibold text-foreground">
                    {@agents_count}
                  </p>
                </div>
                <div class="flex size-11 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                  <.icon name="hero-cpu-chip" class="size-5" />
                </div>
              </div>
              <p class="mt-3 text-sm text-muted-foreground">
                Reusable assistants ready for chat and delegation.
              </p>
            </div>

            <div
              id="dashboard-stat-tools"
              class="rounded-2xl border border-border bg-card p-5 shadow-sm"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="space-y-1">
                  <p class="text-sm font-medium text-muted-foreground">Custom tools</p>
                  <p id="dashboard-stat-tools-value" class="text-3xl font-semibold text-foreground">
                    {@tools_count}
                  </p>
                </div>
                <div class="flex size-11 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                  <.icon name="hero-wrench-screwdriver" class="size-5" />
                </div>
              </div>
              <p class="mt-3 text-sm text-muted-foreground">
                Saved HTTP integrations your agents can call.
              </p>
            </div>

            <div
              id="dashboard-stat-conversations"
              class="rounded-2xl border border-border bg-card p-5 shadow-sm"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="space-y-1">
                  <p class="text-sm font-medium text-muted-foreground">Conversations</p>
                  <p
                    id="dashboard-stat-conversations-value"
                    class="text-3xl font-semibold text-foreground"
                  >
                    {@conversations_count}
                  </p>
                </div>
                <div class="flex size-11 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                  <.icon name="hero-chat-bubble-left-right" class="size-5" />
                </div>
              </div>
              <p class="mt-3 text-sm text-muted-foreground">
                Active or past chat rooms in your workspace.
              </p>
            </div>
          </div>

          <div class="grid gap-6 xl:grid-cols-2">
            <section
              id="dashboard-recent-chats"
              class="rounded-3xl border border-border bg-card p-6 shadow-sm"
            >
              <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold text-foreground">Recent conversations</h2>
                  <p class="text-sm text-muted-foreground">
                    Jump back into the chat rooms you touched most recently.
                  </p>
                </div>

                <.link navigate={recent_chats_destination(@providers_count, @agents_count)}>
                  <.button variant="outline" class="gap-2">
                    <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                    {recent_chats_action_label(@providers_count, @agents_count)}
                  </.button>
                </.link>
              </div>

              <div class="mt-6 space-y-3">
                <%= if @recent_chat_rooms == [] do %>
                  <div
                    id="dashboard-empty-chats"
                    class="rounded-2xl border border-dashed border-border bg-muted/30 p-6 text-sm text-muted-foreground"
                  >
                    <p class="font-medium text-foreground">
                      {recent_chats_empty_title(@providers_count, @agents_count)}
                    </p>
                    <p class="mt-2">{recent_chats_empty_copy(@providers_count, @agents_count)}</p>
                  </div>
                <% else %>
                  <.link
                    :for={chat_room <- @recent_chat_rooms}
                    id={"recent-chat-#{chat_room.id}"}
                    navigate={~p"/chat/#{chat_room.id}"}
                    class="group flex items-center justify-between gap-4 rounded-2xl border border-border/70 bg-background/60 px-4 py-4 transition hover:border-primary/30 hover:bg-accent/30"
                  >
                    <div class="min-w-0">
                      <p class="truncate font-medium text-foreground">{chat_room_title(chat_room)}</p>
                      <div class="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                        <span>{agent_count_label(length(chat_room.agents))}</span>
                        <span aria-hidden="true">&bull;</span>
                        <span>{format_timestamp(chat_room.updated_at)}</span>
                      </div>
                    </div>

                    <span class="inline-flex size-9 shrink-0 items-center justify-center rounded-full bg-muted text-muted-foreground transition group-hover:bg-primary/10 group-hover:text-primary">
                      <.icon name="hero-arrow-right" class="size-4" />
                    </span>
                  </.link>
                <% end %>
              </div>
            </section>

            <section
              id="dashboard-recent-agents"
              class="rounded-3xl border border-border bg-card p-6 shadow-sm"
            >
              <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold text-foreground">Recently added agents</h2>
                  <p class="text-sm text-muted-foreground">
                    Keep an eye on the assistants you configured most recently.
                  </p>
                </div>

                <.link navigate={recent_agents_destination(@providers_count)}>
                  <.button variant="outline" class="gap-2">
                    <.icon name="hero-cpu-chip" class="size-4" />
                    {recent_agents_action_label(@providers_count)}
                  </.button>
                </.link>
              </div>

              <div class="mt-6 space-y-3">
                <%= if @recent_agents == [] do %>
                  <div
                    id="dashboard-empty-agents"
                    class="rounded-2xl border border-dashed border-border bg-muted/30 p-6 text-sm text-muted-foreground"
                  >
                    <p class="font-medium text-foreground">
                      {recent_agents_empty_title(@providers_count)}
                    </p>
                    <p class="mt-2">{recent_agents_empty_copy(@providers_count)}</p>
                  </div>
                <% else %>
                  <div
                    :for={agent <- @recent_agents}
                    id={"recent-agent-#{agent.id}"}
                    class="rounded-2xl border border-border/70 bg-background/60 px-4 py-4"
                  >
                    <div class="flex items-start justify-between gap-4">
                      <div class="min-w-0 space-y-1">
                        <p class="truncate font-medium text-foreground">{agent.name}</p>
                        <div class="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                          <span>{provider_label(agent)}</span>
                          <span aria-hidden="true">&bull;</span>
                          <span>{model_name(agent)}</span>
                        </div>
                      </div>

                      <div class="inline-flex items-center gap-2 rounded-full border border-border bg-muted/50 px-3 py-1.5 text-xs font-medium text-foreground">
                        <.icon name="hero-wrench-screwdriver" class="size-3.5 text-muted-foreground" />
                        <span>{tool_count_label(length(agent.tools))}</span>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </section>
          </div>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end

  defp primary_action(0, _agents_count, _conversations_count, true) do
    %{href: ~p"/providers", label: "Connect a provider", icon: "hero-server-stack"}
  end

  defp primary_action(_providers_count, 0, _conversations_count, true) do
    %{href: ~p"/agents/new", label: "Create your first agent", icon: "hero-cpu-chip"}
  end

  defp primary_action(_providers_count, _agents_count, 0, true) do
    %{href: ~p"/chat", label: "Start your first chat", icon: "hero-chat-bubble-left-right"}
  end

  defp primary_action(_providers_count, _agents_count, _conversations_count, true) do
    %{href: ~p"/chat", label: "Open chat workspace", icon: "hero-chat-bubble-left-right"}
  end

  defp primary_action(_providers_count, agents_count, 0, false) when agents_count > 0 do
    %{href: ~p"/chat", label: "Start your first chat", icon: "hero-chat-bubble-left-right"}
  end

  defp primary_action(_providers_count, agents_count, conversations_count, false)
       when agents_count > 0 and conversations_count > 0 do
    %{href: ~p"/chat", label: "Open chat workspace", icon: "hero-chat-bubble-left-right"}
  end

  defp primary_action(_providers_count, _agents_count, _conversations_count, false), do: nil

  defp workspace_status_label(0, _agents_count, _conversations_count), do: "Setup required"
  defp workspace_status_label(_providers_count, 0, _conversations_count), do: "Agents missing"
  defp workspace_status_label(_providers_count, _agents_count, 0), do: "Ready for first chat"

  defp workspace_status_label(_providers_count, _agents_count, _conversations_count),
    do: "Workspace active"

  defp workspace_status_icon(0, _agents_count, _conversations_count), do: "hero-server-stack"
  defp workspace_status_icon(_providers_count, 0, _conversations_count), do: "hero-cpu-chip"
  defp workspace_status_icon(_providers_count, _agents_count, 0), do: "hero-sparkles"

  defp workspace_status_icon(_providers_count, _agents_count, _conversations_count),
    do: "hero-bolt"

  defp hero_copy(organization_name, email, 0, _agents_count, _conversations_count, true) do
    "#{organization_name} is active for #{email}. Connect a provider first so this workspace can create agents and start chatting."
  end

  defp hero_copy(organization_name, email, _providers_count, 0, _conversations_count, true) do
    "#{organization_name} is active for #{email}. Providers are ready, so the next step is creating an agent for this workspace."
  end

  defp hero_copy(organization_name, email, _providers_count, _agents_count, 0, true) do
    "#{organization_name} is configured for #{email}. Start the first chat to see recent conversations and activity show up here."
  end

  defp hero_copy(
         organization_name,
         email,
         providers_count,
         agents_count,
         conversations_count,
         true
       ) do
    "#{organization_name} is active for #{email}. You have #{providers_count} providers, #{agents_count} agents, and #{conversations_count} conversations in motion."
  end

  defp hero_copy(organization_name, email, _providers_count, 0, _conversations_count, false) do
    "#{organization_name} is active for #{email}. An owner or admin needs to add providers and agents before members can start chatting."
  end

  defp hero_copy(organization_name, email, _providers_count, _agents_count, 0, false) do
    "#{organization_name} is ready for #{email}. Start the first chat to begin working inside this workspace."
  end

  defp hero_copy(
         organization_name,
         email,
         _providers_count,
         agents_count,
         conversations_count,
         false
       ) do
    "#{organization_name} is active for #{email}. This workspace already has #{agents_count} agents and #{conversations_count} conversations available."
  end

  defp recent_chats_destination(0, _agents_count), do: ~p"/providers"
  defp recent_chats_destination(_providers_count, 0), do: ~p"/agents/new"
  defp recent_chats_destination(_providers_count, _agents_count), do: ~p"/chat"

  defp recent_chats_action_label(0, _agents_count), do: "Add provider"
  defp recent_chats_action_label(_providers_count, 0), do: "Create agent"
  defp recent_chats_action_label(_providers_count, _agents_count), do: "Open chats"

  defp recent_chats_empty_title(0, _agents_count),
    do: "No conversations yet because the workspace still needs a provider."

  defp recent_chats_empty_title(_providers_count, 0),
    do: "No conversations yet because there are no agents to chat with."

  defp recent_chats_empty_title(_providers_count, _agents_count), do: "No conversations yet."

  defp recent_chats_empty_copy(0, _agents_count) do
    "Add a provider first, then create an agent and start a chat from the workspace."
  end

  defp recent_chats_empty_copy(_providers_count, 0) do
    "Create at least one agent and your next chat will appear here automatically."
  end

  defp recent_chats_empty_copy(_providers_count, _agents_count) do
    "Start a new chat to build up recent conversation history."
  end

  defp recent_agents_destination(0), do: ~p"/providers"
  defp recent_agents_destination(_providers_count), do: ~p"/agents"

  defp recent_agents_action_label(0), do: "Add provider"
  defp recent_agents_action_label(_providers_count), do: "Manage agents"

  defp recent_agents_empty_title(0), do: "No agents yet because there is no provider configured."
  defp recent_agents_empty_title(_providers_count), do: "No agents created yet."

  defp recent_agents_empty_copy(0) do
    "Connect a provider first so the agent form can load available models."
  end

  defp recent_agents_empty_copy(_providers_count) do
    "Create your first agent to save prompts, model choices, and enabled tools."
  end

  defp chat_room_title(%{title: title}) when title in [nil, ""], do: "Untitled conversation"
  defp chat_room_title(%{title: title}), do: title

  defp provider_label(%{provider: provider}) do
    provider.name || String.capitalize(provider.provider)
  end

  defp model_name(%{model: model}) do
    case String.split(model, ":", parts: 2) do
      [_provider, model_name] -> model_name
      [model_name] -> model_name
    end
  end

  defp tool_count_label(1), do: "1 tool"
  defp tool_count_label(count), do: "#{count} tools"

  defp agent_count_label(1), do: "1 agent"
  defp agent_count_label(count), do: "#{count} agents"

  defp format_timestamp(%DateTime{} = timestamp), do: Calendar.strftime(timestamp, "%b %d, %H:%M")

  defp organization_role_label("owner"), do: "Owner"
  defp organization_role_label("admin"), do: "Admin"
  defp organization_role_label("member"), do: "Member"
  defp organization_role_label(_role), do: "Member"
end
