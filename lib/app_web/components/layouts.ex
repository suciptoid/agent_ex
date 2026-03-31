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
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <nav class="flex items-center gap-4">
        <.link navigate={~p"/"} class="text-sm hover:text-gray-600 dark:hover:text-gray-300">
          Website
        </.link>
        <.link navigate={~p"/"} class="text-sm hover:text-gray-600 dark:hover:text-gray-300">
          GitHub
        </.link>
        <.link navigate={~p"/providers"} class="text-sm hover:text-gray-600 dark:hover:text-gray-300">
          Providers
        </.link>
        <.theme_toggle />
        <.button navigate={~p"/"}>
          Get Started <span aria-hidden="true">&rarr;</span>
        </.button>
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

  slot :inner_block, required: true

  def dashboard(assigns) do
    ~H"""
    <div
      id="dashboard-layout"
      class="h-screen flex bg-background overflow-hidden"
      phx-hook=".SidebarState"
      data-sidebar-collapsed="false"
    >
      <%!-- Mobile overlay (tap to close sidebar) --%>
      <div
        data-sidebar-toggle
        class={[
          "fixed inset-0 bg-black/50 z-20 transition-opacity duration-300 lg:hidden pointer-events-auto opacity-100",
          "[[data-sidebar-collapsed=true]_&]:opacity-0",
          "[[data-sidebar-collapsed=true]_&]:pointer-events-none"
        ]}
      />

      <%!-- Sidebar --%>
      <aside class={[
        "relative z-30 h-full bg-card border-r border-border transition-all duration-300 ease-in-out flex flex-col flex-shrink-0",
        "w-56",
        "[[data-sidebar-collapsed=true]_&]:-translate-x-full lg:[[data-sidebar-collapsed=true]_&]:translate-x-0",
        "lg:[[data-sidebar-collapsed=true]_&]:w-14"
      ]}>
        <%!-- Sidebar top: hamburger + logo --%>
        <div class="flex items-center gap-2 px-3 py-3 border-b border-border">
          <button
            type="button"
            class="flex-shrink-0 p-1.5 rounded-lg text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
            aria-label="Toggle sidebar"
            data-sidebar-toggle
            aria-expanded="true"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <a
            href={~p"/dashboard"}
            class="flex items-center gap-2 overflow-hidden [[data-sidebar-collapsed=true]_&]:hidden"
          >
            <img src={~p"/images/logo.svg"} width="24" />
            <span class="text-base font-semibold text-foreground whitespace-nowrap">AgentEx</span>
          </a>
        </div>

        <%!-- Navigation Links --%>
        <nav class="flex-1 px-2 py-3 space-y-0.5 overflow-y-auto">
          <.link
            navigate={~p"/dashboard"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-muted-foreground rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-home" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Dashboard</span>
          </.link>

          <.link
            navigate={~p"/providers"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-muted-foreground rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-server-stack" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Providers</span>
          </.link>

          <.link
            navigate={~p"/tools/create"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-muted-foreground rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-wrench-screwdriver" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Tools</span>
          </.link>

          <.link
            navigate={~p"/agents"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-muted-foreground rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-cpu-chip" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Agents</span>
          </.link>

          <.link
            navigate={~p"/chat"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-muted-foreground rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-chat-bubble-left-right" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Chat</span>
          </.link>
        </nav>

        <%!-- User Section (Bottom) — theme toggle hidden inside menu --%>
        <div class="p-3 border-t border-border">
          <div class="[[data-sidebar-collapsed=true]_&]:hidden">
            <.menu_button
              id="sidebar-user-menu"
              variant="unstyled"
              content_class="w-56 z-50 bg-popover text-popover-foreground rounded-md border border-border p-1 shadow-md mb-2 aria-hidden:hidden not-aria-hidden:animate-in not-aria-hidden:fade-in-0 not-aria-hidden:zoom-in-95 aria-hidden:animate-out aria-hidden:fade-out-0 aria-hidden:zoom-out-95"
              class="flex w-full items-center gap-2.5 rounded-xl border border-border bg-background px-2.5 py-2 text-left transition hover:bg-accent/60"
            >
              <.icon name="hero-user-circle" class="size-7 text-muted-foreground shrink-0" />
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-medium text-foreground">
                  {@current_scope.user.email}
                </p>
              </div>
              <.icon name="hero-chevron-up-down" class="size-4 text-muted-foreground shrink-0" />
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
              <.icon name="hero-user-circle" class="size-6" />
            </span>
          </div>
        </div>
      </aside>

      <%!-- Main Content --%>
      <main class="flex-1 min-w-0 h-full overflow-hidden flex flex-col">
        <div class="flex-1 overflow-y-auto p-4 sm:p-5 lg:p-6 h-full flex flex-col">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SidebarState">
        export default {
          mounted() {
            const root = this.el;
            const toggles = root.querySelectorAll("[data-sidebar-toggle]");
            const setState = (collapsed) => {
              root.dataset.sidebarCollapsed = String(collapsed);
              toggles.forEach((toggle) => {
                toggle.setAttribute("aria-expanded", String(!collapsed));
              });
              localStorage.setItem("sidebar_collapsed", String(collapsed));
            };

            const stored = localStorage.getItem("sidebar_collapsed");
            setState(stored === "true");

            toggles.forEach((toggle) => {
              toggle.addEventListener("click", () => {
                const next = root.dataset.sidebarCollapsed !== "true";
                setState(next);
              });
            });
          }
        }
      </script>
    </div>
    """
  end
end
