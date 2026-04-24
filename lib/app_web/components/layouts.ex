defmodule AppWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AppWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="flex items-center justify-between px-4 sm:px-6 lg:px-8 py-4 border-b border-gray-200 dark:border-gray-700">
      <div class="flex-1">
        <a href="/" class="flex w-fit items-center gap-2">
          <svg viewBox="0 0 71 48" class="h-8" aria-hidden="true">
            <path
              d="m26.371 33.477-.552-.1c-3.92-.729-6.397-3.1-7.57-6.829-.733-2.324.597-4.035 3.035-4.148 1.995-.092 3.362 1.055 4.57 2.39 1.557 1.72 2.984 3.558 4.514 5.305 2.202 2.515 4.797 4.136 8.347 3.634 3.183-.448 5.958-1.725 8.371-3.828.363-.316.761-.592 1.144-.886l-.241-.284c-2.027.63-4.093.841-6.205.735-3.195-.16-6.24-.828-8.964-2.582-2.486-1.601-4.319-3.746-5.19-6.611-.704-2.315.736-3.934 3.135-3.6.948.133 1.746.56 2.463 1.165.583.493 1.143 1.015 1.738 1.493 2.8 2.25 6.712 2.375 10.265-.068-5.842-.026-9.817-3.24-13.308-7.313-1.366-1.594-2.7-3.216-4.095-4.785-2.698-3.036-5.692-5.71-9.79-6.623C12.8-.623 7.745.14 2.893 2.361 1.926 2.804.997 3.319 0 4.149c.494 0 .763.006 1.032 0 2.446-.064 4.28 1.023 5.602 3.024.962 1.457 1.415 3.104 1.761 4.798.513 2.515.247 5.078.544 7.605.761 6.494 4.08 11.026 10.26 13.346 2.267.852 4.591 1.135 7.172.555ZM10.751 3.852c-.976.246-1.756-.148-2.56-.962 1.377-.343 2.592-.476 3.897-.528-.107.848-.607 1.306-1.336 1.49Zm32.002 37.924c-.085-.626-.62-.901-1.04-1.228-1.857-1.446-4.03-1.958-6.333-2-1.375-.026-2.735-.128-4.031-.61-.595-.22-1.26-.505-1.244-1.272.015-.78.693-1 1.31-1.184.505-.15 1.026-.247 1.6-.382-1.46-.936-2.886-1.065-4.787-.3-2.993 1.202-5.943 1.06-8.926-.017-1.684-.608-3.179-1.563-4.735-2.408l-.043.03a2.96 2.96 0 0 0 .04-.029c-.038-.117-.107-.12-.197-.054l.122.107c1.29 2.115 3.034 3.817 5.004 5.271 3.793 2.8 7.936 4.471 12.784 3.73A66.714 66.714 0 0 1 37 40.877c1.98-.16 3.866.398 5.753.899Zm-9.14-30.345c-.105-.076-.206-.266-.42-.069 1.745 2.36 3.985 4.098 6.683 5.193 4.354 1.767 8.773 2.07 13.293.51 3.51-1.21 6.033-.028 7.343 3.38.19-3.955-2.137-6.837-5.843-7.401-2.084-.318-4.01.373-5.962.94-5.434 1.575-10.485.798-15.094-2.553Zm27.085 15.425c.708.059 1.416.123 2.124.185-1.6-1.405-3.55-1.517-5.523-1.404-3.003.17-5.167 1.903-7.14 3.972-1.739 1.824-3.31 3.87-5.903 4.604.043.078.054.117.066.117.35.005.699.021 1.047.005 3.768-.17 7.317-.965 10.14-3.7.89-.86 1.685-1.817 2.544-2.71.716-.746 1.584-1.159 2.645-1.07Zm-8.753-4.67c-2.812.246-5.254 1.409-7.548 2.943-1.766 1.18-3.654 1.738-5.776 1.37-.374-.066-.75-.114-1.124-.17l-.013.156c.135.07.265.151.405.207.354.14.702.308 1.07.395 4.083.971 7.992.474 11.516-1.803 2.221-1.435 4.521-1.707 7.013-1.336.252.038.503.083.756.107.234.022.479.255.795.003-2.179-1.574-4.526-2.096-7.094-1.872Zm-10.049-9.544c1.475.051 2.943-.142 4.486-1.059-.452.04-.643.04-.827.076-2.126.424-4.033-.04-5.733-1.383-.623-.493-1.257-.974-1.889-1.457-2.503-1.914-5.374-2.555-8.514-2.5.05.154.054.26.108.315 3.417 3.455 7.371 5.836 12.369 6.008Zm24.727 17.731c-2.114-2.097-4.952-2.367-7.578-.537 1.738.078 3.043.632 4.101 1.728.374.388.763.768 1.182 1.106 1.6 1.29 4.311 1.352 5.896.155-1.861-.726-1.861-.726-3.601-2.452Zm-21.058 16.06c-1.858-3.46-4.981-4.24-8.59-4.008a9.667 9.667 0 0 1 2.977 1.39c.84.586 1.547 1.311 2.243 2.055 1.38 1.473 3.534 2.376 4.962 2.07-.656-.412-1.238-.848-1.592-1.507Zm17.29-19.32c0-.023.001-.045.003-.068l-.006.006.006-.006-.036-.004.021.018.012.053Zm-20 14.744a7.61 7.61 0 0 0-.072-.041.127.127 0 0 0 .015.043c.005.008.038 0 .058-.002Zm-.072-.041-.008-.034-.008.01.008-.01-.022-.006.005.026.024.014Z"
              fill="#FD4F00"
            />
          </svg>
          <span class="text-lg font-semibold tracking-tight">AgentEx</span>
        </a>
      </div>
      <nav class="flex items-center gap-4">
        <a
          href="https://github.com/suciptoid/agent_ex"
          target="_blank"
          rel="noopener noreferrer"
          class="text-sm text-muted-foreground transition-colors hover:text-foreground"
        >
          GitHub
        </a>
        <.theme_toggle />
        <%= if @current_scope && @current_scope.user do %>
          <.button navigate={~p"/dashboard"}>
            Dashboard <span aria-hidden="true">&rarr;</span>
          </.button>
        <% else %>
          <.button navigate={~p"/users/log-in"}>
            Sign In <span aria-hidden="true">&rarr;</span>
          </.button>
        <% end %>
      </nav>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <PUI.Flash.flash_group flash={@flash} position="top-right" />

      <div
        id="client-error"
        class="fixed top-4 right-4 z-50 hidden w-full max-w-sm"
        phx-disconnected={JS.remove_class("hidden", to: "#client-error")}
        phx-connected={JS.add_class("hidden", to: "#client-error")}
        hidden
      >
        <.alert variant="destructive">
          <:icon>
            <.icon name="hero-exclamation-triangle" class="size-4" />
          </:icon>
          <:title>{gettext("We can't find the internet")}</:title>
          <:description>
            <span class="inline-flex items-center gap-1">
              {gettext("Attempting to reconnect")}
              <.icon name="hero-arrow-path" class="size-3 motion-safe:animate-spin" />
            </span>
          </:description>
        </.alert>
      </div>

      <div
        id="server-error"
        class="fixed top-4 right-4 z-50 hidden w-full max-w-sm"
        phx-disconnected={JS.remove_class("hidden", to: "#server-error")}
        phx-connected={JS.add_class("hidden", to: "#server-error")}
        hidden
      >
        <.alert variant="destructive">
          <:icon>
            <.icon name="hero-exclamation-circle" class="size-4" />
          </:icon>
          <:title>{gettext("Something went wrong!")}</:title>
          <:description>
            <span class="inline-flex items-center gap-1">
              {gettext("Attempting to reconnect")}
              <.icon name="hero-arrow-path" class="size-3 motion-safe:animate-spin" />
            </span>
          </:description>
        </.alert>
      </div>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row justify-between items-center border-2 border-gray-300 dark:border-gray-600 bg-gray-200 dark:bg-gray-700 rounded-full p-1">
      <div class="absolute w-6 h-6 rounded-full bg-white dark:bg-gray-800 shadow-sm left-1 [[data-theme=light]_&]:left-[calc(50%-12px)] [[data-theme=dark]_&]:left-[calc(100%-28px)] transition-[left]" />

      <button
        class="relative flex items-center justify-center w-6 h-6 cursor-pointer z-10"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="System theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="relative flex items-center justify-center w-6 h-6 cursor-pointer z-10"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="relative flex items-center justify-center w-6 h-6 cursor-pointer z-10"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  defp sidebar_user_label(%{email: email}) when is_binary(email) do
    case String.split(email, "@", parts: 2) do
      [label, _domain] when label != "" -> label
      _ -> email
    end
  end

  defp sidebar_user_label(_user), do: "Account"

  @doc """
  Renders the dashboard layout with collapsible sidebar.
  The sidebar contains the hamburger toggle, logo, nav links, and user menu.
  No top header — layout is [sidebar | content].

  ## Examples

      <Layouts.dashboard flash={@flash} current_scope={@current_scope}>
        <h1>Dashboard Content</h1>
      </Layouts.dashboard>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.html.pm/phoenix/scopes.html)"

  attr :sidebar_chat_rooms, :list, default: [], doc: "list of chat rooms for the sidebar"

  attr :sidebar_organizations, :list,
    default: [],
    doc: "organization memberships for the sidebar switcher"

  slot :inner_block, required: true

  def dashboard(assigns) do
    ~H"""
    <div
      id="dashboard-layout"
      class="relative flex h-screen w-full bg-background overflow-hidden"
      phx-hook=".SidebarState"
      data-sidebar-collapsed="false"
    >
      <%!-- Mobile toggle --%>
      <button
        type="button"
        class={[
          "fixed left-4 top-4 z-30 flex h-11 w-11 items-center justify-center rounded-2xl border border-border bg-card/95 text-foreground shadow-lg backdrop-blur transition-all duration-300 hover:bg-accent lg:hidden",
          "[[data-sidebar-collapsed=false]_&]:pointer-events-none",
          "[[data-sidebar-collapsed=false]_&]:opacity-0",
          "[[data-sidebar-collapsed=false]_&]:translate-x-2"
        ]}
        aria-label="Open sidebar"
        data-sidebar-toggle
        aria-expanded="false"
      >
        <.icon name="hero-bars-3" class="size-5" />
      </button>

      <%!-- Mobile overlay (tap to close sidebar) --%>
      <div
        data-sidebar-toggle
        class={[
          "fixed inset-0 z-40 bg-black/45 backdrop-blur-sm transition-opacity duration-300 lg:hidden pointer-events-auto opacity-100",
          "[[data-sidebar-collapsed=true]_&]:opacity-0",
          "[[data-sidebar-collapsed=true]_&]:pointer-events-none"
        ]}
      />

      <%!-- Sidebar --%>
      <aside class={[
        "fixed inset-y-2 left-2 z-50 flex h-[calc(100vh-1rem)] max-w-[calc(100vw-1rem)] flex-col overflow-hidden rounded-xl border border-border bg-secondary shadow-xl transition-all duration-300 ease-in-out",
        "w-[240px]",
        "[[data-sidebar-collapsed=true]_&]:-translate-x-[calc(100%+0.75rem)] lg:[[data-sidebar-collapsed=true]_&]:translate-x-0",
        "lg:relative lg:inset-y-0 lg:left-0 lg:h-full lg:max-w-none lg:rounded-none lg:border-y-0 lg:border-l-0 lg:shadow-none lg:w-[240px]",
        "lg:[[data-sidebar-collapsed=true]_&]:w-[52px]"
      ]}>
        <%!-- Sidebar top: hamburger + app name --%>
        <div class="flex items-center gap-2 px-2.5 py-2 border-b border-border">
          <button
            type="button"
            class="flex-shrink-0 p-1 rounded-md text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
            aria-label="Toggle sidebar"
            data-sidebar-toggle
            aria-expanded="true"
          >
            <.icon name="hero-bars-3" class="size-4.5" />
          </button>

          <div class="min-w-0 flex-1 [[data-sidebar-collapsed=true]_&]:hidden">
            <p class="truncate text-sm font-semibold tracking-tight text-foreground">
              AgentEx
            </p>
          </div>
        </div>

        <%!-- Navigation Links --%>
        <nav class="px-1.5 py-2 space-y-0.5">
          <div class="[[data-sidebar-collapsed=true]_&]:hidden py-1 *:w-full">
            <.menu_button
              id="sidebar-organization-switcher"
              variant="unstyled"
              content_class="w-64 z-50 bg-popover text-popover-foreground rounded-md border border-border p-1 shadow-md mb-2 aria-hidden:hidden not-aria-hidden:animate-in not-aria-hidden:fade-in-0 not-aria-hidden:zoom-in-95 aria-hidden:animate-out aria-hidden:fade-out-0 aria-hidden:zoom-out-95"
              class="flex w-full! min-w-0 items-center gap-2 rounded-lg border border-border/60 bg-background/70 px-2 py-1.5 text-left shadow-none transition hover:bg-accent/60"
            >
              <div class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <.icon name="hero-building-office-2" class="size-4" />
              </div>

              <div class="min-w-0 flex-1 overflow-hidden">
                <p class="truncate text-xs font-semibold text-foreground">
                  {active_organization_name(@current_scope)}
                </p>
                <p class="truncate text-[10px] text-muted-foreground">
                  {active_organization_subtitle(@current_scope, @sidebar_organizations)}
                </p>
              </div>

              <.icon name="hero-chevron-up-down" class="size-3.5 shrink-0 text-muted-foreground" />

              <:items>
                <.menu_item
                  :for={membership <- @sidebar_organizations}
                  href={~p"/organizations/switch/#{membership.organization_id}"}
                >
                  <div class="flex min-w-0 flex-1 items-center gap-2">
                    <span class="truncate">{membership.organization.name}</span>
                    <span
                      :if={organization_active?(membership, @current_scope)}
                      class="inline-flex items-center rounded-full border border-primary/20 bg-primary/10 px-1.5 py-0.5 text-[10px] font-medium text-primary"
                    >
                      Current
                    </span>
                  </div>
                  <span class="text-xs text-muted-foreground">
                    {String.capitalize(membership.role)}
                  </span>
                </.menu_item>
                <.menu_separator />
                <.menu_item
                  :if={organization_manager?(@current_scope)}
                  navigate={~p"/organizations/settings"}
                >
                  <.icon name="hero-adjustments-horizontal" class="size-4" /> Organization Settings
                </.menu_item>
                <.menu_separator :if={organization_manager?(@current_scope)} />
                <.menu_item navigate={~p"/organizations/select?new=true"}>
                  <.icon name="hero-plus" class="size-4" /> Create New Organization
                </.menu_item>
              </:items>
            </.menu_button>
          </div>

          <.link
            navigate={~p"/dashboard"}
            data-sidebar-nav-link
            data-sidebar-match="exact"
            class="flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-sm font-medium text-foreground/75 transition-colors hover:bg-accent hover:text-foreground aria-[current=page]:bg-background/80 aria-[current=page]:text-foreground aria-[current=page]:shadow-sm"
          >
            <.icon name="hero-home" class="size-4.5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Dashboard</span>
          </.link>

          <.link
            navigate={~p"/providers"}
            data-sidebar-nav-link
            data-sidebar-match="prefix"
            class="flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-sm font-medium text-foreground/75 transition-colors hover:bg-accent hover:text-foreground aria-[current=page]:bg-background/80 aria-[current=page]:text-foreground aria-[current=page]:shadow-sm"
          >
            <.icon name="hero-server-stack" class="size-4.5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Providers</span>
          </.link>

          <.link
            navigate={~p"/tools/list"}
            data-sidebar-nav-link
            data-sidebar-match="prefix"
            data-sidebar-prefix="/tools"
            class="flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-sm font-medium text-foreground/75 transition-colors hover:bg-accent hover:text-foreground aria-[current=page]:bg-background/80 aria-[current=page]:text-foreground aria-[current=page]:shadow-sm"
          >
            <.icon name="hero-wrench-screwdriver" class="size-4.5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Tools</span>
          </.link>

          <div id="sidebar-agents-group" class="space-y-0.5">
            <.link
              navigate={~p"/agents"}
              data-sidebar-nav-link
              data-sidebar-match="prefix"
              class="flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-sm font-medium text-foreground/75 transition-colors hover:bg-accent hover:text-foreground aria-[current=page]:bg-background/80 aria-[current=page]:text-foreground aria-[current=page]:shadow-sm"
            >
              <.icon name="hero-cpu-chip" class="size-4.5 flex-shrink-0" />
              <span class="[[data-sidebar-collapsed=true]_&]:hidden">Agents</span>
            </.link>

            <.link
              id="sidebar-tasks-link"
              navigate={~p"/tasks"}
              data-sidebar-nav-link
              data-sidebar-match="prefix"
              class="flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-sm font-medium text-foreground/75 transition-colors hover:bg-accent hover:text-foreground aria-[current=page]:bg-background/80 aria-[current=page]:text-foreground aria-[current=page]:shadow-sm"
            >
              <.icon name="hero-clock" class="size-4.5 flex-shrink-0" />
              <span class="[[data-sidebar-collapsed=true]_&]:hidden">Tasks</span>
            </.link>

            <.link
              id="sidebar-gateways-link"
              navigate={~p"/gateways"}
              data-sidebar-nav-link
              data-sidebar-match="prefix"
              class="flex items-center gap-2.5 rounded-lg px-2 py-1.5 text-sm font-medium text-foreground/75 transition-colors hover:bg-accent hover:text-foreground aria-[current=page]:bg-background/80 aria-[current=page]:text-foreground aria-[current=page]:shadow-sm"
            >
              <.icon name="hero-signal" class="size-4.5 flex-shrink-0" />
              <span class="[[data-sidebar-collapsed=true]_&]:hidden">Gateways</span>
            </.link>
          </div>
        </nav>

        <%!-- Chat History --%>
        <div class="flex-1 overflow-y-auto border-t border-border [[data-sidebar-collapsed=true]_&]:hidden">
          <div class="px-1.5 py-1">
            <div class="sticky top-0 z-10 mb-1 flex items-center justify-between bg-secondary px-2 py-1.5">
              <h3 class="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">
                Chats
              </h3>
              <div class="flex items-center gap-1">
                <.link
                  id="sidebar-all-chats-link"
                  navigate={~p"/chat/all"}
                  class="inline-flex items-center justify-center size-4.5 rounded text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
                  title="All chats"
                >
                  <.icon name="hero-queue-list" class="size-3" />
                </.link>
                <.link
                  id="sidebar-new-chat-link"
                  navigate={~p"/chat"}
                  class="inline-flex items-center justify-center size-4.5 rounded text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
                  title="New Chat"
                >
                  <.icon name="hero-plus" class="size-3" />
                </.link>
              </div>
            </div>
            <div class="space-y-0.5">
              <div
                :for={chat <- @sidebar_chat_rooms}
                class="group/sidebar flex items-center gap-2 rounded-md py-0.5 transition-colors hover:bg-background/85 hover:text-foreground hover:shadow-sm"
              >
                <.link
                  navigate={~p"/chat/#{chat.id}"}
                  data-sidebar-chat-link
                  class="flex min-w-0 flex-1 items-center gap-2 rounded-md px-2 py-1.5 text-xs text-foreground/65 transition-colors aria-[current=page]:font-semibold aria-[current=page]:text-foreground"
                >
                  <span
                    :if={chat.approval_needed}
                    id={"sidebar-chat-approval-icon-#{chat.id}"}
                    class="inline-flex size-4 flex-shrink-0 items-center justify-center rounded-full bg-amber-500/10 text-amber-500"
                    title="Pending approval"
                  >
                    <.icon name="hero-exclamation-triangle" class="size-2.5" />
                  </span>
                  <span
                    :if={not chat.approval_needed and chat.gateway_linked}
                    id={"sidebar-chat-gateway-icon-#{chat.id}"}
                    class="inline-flex size-4 flex-shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary"
                    title="Linked to a gateway channel"
                  >
                    <.icon name="hero-signal" class="size-2.5" />
                  </span>
                  <span class="min-w-0 flex-1 truncate">{sidebar_chat_room_title(chat)}</span>
                  <span class="inline-flex flex-shrink-0 items-center gap-1">
                    <span
                      :if={chat.loading}
                      id={"sidebar-chat-loading-#{chat.id}"}
                      class="inline-flex size-3.5 items-center justify-center text-muted-foreground"
                    >
                      <.icon name="hero-arrow-path" class="size-3 animate-spin" />
                    </span>
                  </span>
                </.link>

                <button
                  id={"sidebar-delete-chat-#{chat.id}"}
                  type="button"
                  phx-click="delete-chat-room"
                  phx-value-id={chat.id}
                  data-confirm="Delete this chat?"
                  class="hidden size-6 flex-shrink-0 items-center justify-center rounded-full text-muted-foreground transition hover:bg-accent hover:text-foreground group-hover/sidebar:flex focus-visible:flex focus-visible:bg-accent focus-visible:text-foreground"
                  title="Delete chat"
                  aria-label="Delete chat"
                >
                  <.icon name="hero-trash" class="size-3.5" />
                </button>
              </div>

              <p
                :if={@sidebar_chat_rooms == []}
                class="px-2 py-1 text-xs text-muted-foreground/60"
              >
                No conversations yet
              </p>
            </div>
          </div>
        </div>

        <%!-- Collapsed chat icon --%>
        <div class="hidden [[data-sidebar-collapsed=true]_&]:flex flex-1 justify-center items-start pt-2 border-t border-border">
          <.link
            navigate={~p"/chat"}
            data-sidebar-nav-link
            data-sidebar-match="prefix"
            class="rounded-lg p-1.5 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground aria-[current=page]:text-foreground"
            title="Chat"
          >
            <.icon name="hero-chat-bubble-left-right" class="size-4.5" />
          </.link>
        </div>

        <%!-- User Section (Bottom) — theme toggle hidden inside menu --%>
        <div class="border-t border-border p-1">
          <div class="[[data-sidebar-collapsed=true]_&]:hidden *:w-full">
            <.menu_button
              id="sidebar-user-menu"
              variant="unstyled"
              content_class="w-56 z-50 bg-popover text-popover-foreground rounded-md border border-border p-1 shadow-md mb-2 aria-hidden:hidden not-aria-hidden:animate-in not-aria-hidden:fade-in-0 not-aria-hidden:zoom-in-95 aria-hidden:animate-out aria-hidden:fade-out-0 aria-hidden:zoom-out-95"
              class="flex w-full! min-w-0 items-center gap-2 overflow-hidden rounded-lg bg-background/70 px-2 py-1.5 text-left shadow-none transition hover:bg-accent/60"
            >
              <.icon name="hero-user-circle" class="size-6 text-muted-foreground shrink-0" />
              <div class="min-w-0 flex-1 overflow-hidden">
                <p class="truncate text-xs font-medium text-foreground">
                  {sidebar_user_label(@current_scope.user)}
                </p>
                <p class="truncate text-[10px] text-muted-foreground">
                  {@current_scope.user.email}
                </p>
              </div>
              <.icon name="hero-chevron-up-down" class="size-3.5 text-muted-foreground shrink-0" />
              <:items>
                <.menu_item navigate={~p"/users/settings"}>
                  <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
                </.menu_item>
                <.menu_separator />
                <div class="px-2 py-2">
                  <.theme_toggle />
                </div>
                <.menu_separator />
                <.menu_item href={~p"/users/log-out"} method="delete" variant="destructive">
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
                </.menu_item>
              </:items>
            </.menu_button>
          </div>
          <%!-- Icon-only user icon when collapsed --%>
          <div class="hidden [[data-sidebar-collapsed=true]_&]:flex justify-center">
            <span class="p-1.5 text-muted-foreground">
              <.icon name="hero-user-circle" class="size-5" />
            </span>
          </div>
        </div>
      </aside>

      <%!-- Main Content --%>
      <main class="flex h-full w-full min-w-0 flex-1 flex-col overflow-hidden">
        <div class="flex h-full flex-1 flex-col overflow-y-auto">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SidebarState">
        export default {
          mounted() {
            this.desktopMedia = window.matchMedia("(min-width: 1024px)");
            this.desktopStorageKey = "sidebar_collapsed_desktop";

            this.applyState = (collapsed, { persistDesktop = true } = {}) => {
              this.collapsed = collapsed;
              this.el.dataset.sidebarCollapsed = String(collapsed);

              this.toggles.forEach((toggle) => {
                toggle.setAttribute("aria-expanded", String(!collapsed));
              });

              if (persistDesktop && this.desktopMedia.matches) {
                localStorage.setItem(this.desktopStorageKey, String(collapsed));
              }
            };

            this.defaultState = () => {
              if (this.desktopMedia.matches) {
                return localStorage.getItem(this.desktopStorageKey) === "true";
              }

              return true;
            };

            this.handleToggle = () => {
              this.applyState(this.el.dataset.sidebarCollapsed !== "true");
            };

            this.handleViewportChange = () => {
              this.applyState(this.defaultState(), { persistDesktop: false });
            };

            this.activePath = () => window.location.pathname.replace(/\/$/, "") || "/";

            this.linkPath = (link) => {
              try {
                return new URL(link.getAttribute("href"), window.location.origin).pathname.replace(/\/$/, "") || "/";
              } catch (_error) {
                return "";
              }
            };

            this.linkMatchesPath = (link, currentPath) => {
              const linkPath = link.dataset.sidebarPrefix || this.linkPath(link);
              const normalizedLinkPath = linkPath.replace(/\/$/, "") || "/";

              if (link.dataset.sidebarMatch === "prefix") {
                return currentPath === normalizedLinkPath ||
                  currentPath.startsWith(`${normalizedLinkPath}/`);
              }

              return currentPath === normalizedLinkPath;
            };

            this.syncActiveLinks = () => {
              const currentPath = this.activePath();

              this.el.querySelectorAll("[data-sidebar-nav-link], [data-sidebar-chat-link]")
                .forEach((link) => {
                  if (this.linkMatchesPath(link, currentPath)) {
                    link.setAttribute("aria-current", "page");
                  } else {
                    link.removeAttribute("aria-current");
                  }
                });
            };

            this.bindToggles = () => {
              this.toggles = Array.from(this.el.querySelectorAll("[data-sidebar-toggle]"));

              this.toggles.forEach((toggle) => {
                toggle.addEventListener("click", this.handleToggle);
              });
            };

            this.unbindToggles = () => {
              (this.toggles || []).forEach((toggle) => {
                toggle.removeEventListener("click", this.handleToggle);
              });
            };

            this.bindToggles();
            this.desktopMedia.addEventListener("change", this.handleViewportChange);
            this.applyState(this.defaultState(), { persistDesktop: false });
            this.syncActiveLinks();
          },

          updated() {
            this.unbindToggles();
            this.bindToggles();
            this.applyState(this.collapsed ?? this.defaultState(), { persistDesktop: false });
            this.syncActiveLinks();
          },

          destroyed() {
            this.unbindToggles();
            this.desktopMedia.removeEventListener("change", this.handleViewportChange);
          }
        }
      </script>
    </div>
    """
  end

  defp active_organization_name(%{organization: %{name: name}}) when is_binary(name), do: name
  defp active_organization_name(_scope), do: "Select organization"

  defp active_organization_subtitle(%{organization_role: role}, _sidebar_organizations)
       when is_binary(role) do
    "#{String.capitalize(role)} access"
  end

  defp active_organization_subtitle(_scope, []), do: "Create your first workspace"
  defp active_organization_subtitle(_scope, _sidebar_organizations), do: "Switch workspace"

  defp organization_manager?(%{organization_role: role}), do: role in ~w(owner admin)
  defp organization_manager?(_scope), do: false

  defp organization_active?(membership, %{organization: %{id: organization_id}}) do
    membership.organization_id == organization_id
  end

  defp organization_active?(_membership, _scope), do: false

  defp sidebar_chat_room_title(%{title: title}) when title in [nil, ""], do: "Untitled"
  defp sidebar_chat_room_title(%{title: title}), do: title
end
