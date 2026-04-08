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
        "fixed inset-y-2 left-2 z-50 flex h-[calc(100vh-1rem)] max-w-[calc(100vw-1rem)] flex-col overflow-hidden rounded-2xl border border-border bg-card shadow-2xl transition-all duration-300 ease-in-out",
        "w-[255px]",
        "[[data-sidebar-collapsed=true]_&]:-translate-x-[calc(100%+0.75rem)] lg:[[data-sidebar-collapsed=true]_&]:translate-x-0",
        "lg:relative lg:inset-y-0 lg:left-0 lg:h-full lg:max-w-none lg:rounded-none lg:border-y-0 lg:border-l-0 lg:shadow-none lg:w-[255px]",
        "lg:[[data-sidebar-collapsed=true]_&]:w-14"
      ]}>
        <%!-- Sidebar top: hamburger + organization switcher --%>
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

          <div class="min-w-0 flex-1 [[data-sidebar-collapsed=true]_&]:hidden">
            <.menu_button
              id="sidebar-organization-switcher"
              variant="unstyled"
              content_class="w-64 z-50 bg-popover text-popover-foreground rounded-md border border-border p-1 shadow-md mb-2 aria-hidden:hidden not-aria-hidden:animate-in not-aria-hidden:fade-in-0 not-aria-hidden:zoom-in-95 aria-hidden:animate-out aria-hidden:fade-out-0 aria-hidden:zoom-out-95"
              class="flex w-full! min-w-0 items-center gap-3 rounded-xl border border-border/60 bg-background/70 px-2.5 py-2 text-left shadow-none transition hover:bg-accent/60"
            >
              <div class="flex size-9 shrink-0 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                <.icon name="hero-building-office-2" class="size-4.5" />
              </div>

              <div class="min-w-0 flex-1 overflow-hidden">
                <p class="truncate text-sm font-semibold text-foreground">
                  {active_organization_name(@current_scope)}
                </p>
                <p class="truncate text-xs text-muted-foreground">
                  {active_organization_subtitle(@current_scope, @sidebar_organizations)}
                </p>
              </div>

              <.icon name="hero-chevron-up-down" class="size-4 shrink-0 text-muted-foreground" />

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
                <.menu_item navigate={~p"/organizations/select?new=true"}>
                  <.icon name="hero-plus" class="size-4" /> Create New Organization
                </.menu_item>
              </:items>
            </.menu_button>
          </div>
        </div>

        <%!-- Navigation Links --%>
        <nav class="px-2 py-3 space-y-0.5">
          <.link
            navigate={~p"/dashboard"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-foreground/75 rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-home" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Dashboard</span>
          </.link>

          <.link
            navigate={~p"/providers"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-foreground/75 rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-server-stack" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Providers</span>
          </.link>

          <.link
            navigate={~p"/tools/list"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-foreground/75 rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-wrench-screwdriver" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Tools</span>
          </.link>

          <.link
            navigate={~p"/agents"}
            class="flex items-center gap-3 px-2.5 py-2 text-sm font-medium text-foreground/75 rounded-lg hover:bg-accent hover:text-foreground transition-colors"
          >
            <.icon name="hero-cpu-chip" class="size-5 flex-shrink-0" />
            <span class="[[data-sidebar-collapsed=true]_&]:hidden">Agents</span>
          </.link>
        </nav>

        <%!-- Chat History --%>
        <div class="flex-1 overflow-y-auto border-t border-border [[data-sidebar-collapsed=true]_&]:hidden">
          <div class="px-2 pb-1">
            <div class="sticky top-0 z-10 mb-1 flex items-center justify-between bg-card px-2.5 pb-2 pt-3">
              <h3 class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Chats
              </h3>
              <.link
                id="sidebar-new-chat-link"
                navigate={~p"/chat"}
                class="inline-flex items-center justify-center size-5 rounded text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
                title="New Chat"
              >
                <.icon name="hero-plus" class="size-3.5" />
              </.link>
            </div>
            <div class="space-y-0.5">
              <.link
                :for={chat <- @sidebar_chat_rooms}
                navigate={~p"/chat/#{chat.id}"}
                class="flex items-center gap-3 px-2.5 py-1.5 text-sm text-foreground/65 rounded-lg hover:bg-accent hover:text-foreground transition-colors"
              >
                <span class="min-w-0 flex-1 truncate">{chat.title || "Untitled"}</span>
                <span
                  :if={chat.loading}
                  id={"sidebar-chat-loading-#{chat.id}"}
                  class="inline-flex size-4 flex-shrink-0 items-center justify-center text-muted-foreground"
                >
                  <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                </span>
              </.link>

              <p
                :if={@sidebar_chat_rooms == []}
                class="px-2.5 py-1.5 text-xs text-muted-foreground/60"
              >
                No conversations yet
              </p>
            </div>
          </div>
        </div>

        <%!-- Collapsed chat icon --%>
        <div class="hidden [[data-sidebar-collapsed=true]_&]:flex flex-1 justify-center pt-3 border-t border-border">
          <.link
            navigate={~p"/chat"}
            class="p-1.5 text-muted-foreground hover:text-foreground transition-colors"
            title="Chat"
          >
            <.icon name="hero-chat-bubble-left-right" class="size-5" />
          </.link>
        </div>

        <%!-- User Section (Bottom) — theme toggle hidden inside menu --%>
        <div class="border-t border-border p-1">
          <div class="[[data-sidebar-collapsed=true]_&]:hidden *:w-full">
            <.menu_button
              id="sidebar-user-menu"
              variant="unstyled"
              content_class="w-56 z-50 bg-popover text-popover-foreground rounded-md border border-border p-1 shadow-md mb-2 aria-hidden:hidden not-aria-hidden:animate-in not-aria-hidden:fade-in-0 not-aria-hidden:zoom-in-95 aria-hidden:animate-out aria-hidden:fade-out-0 aria-hidden:zoom-out-95"
              class="flex w-full! min-w-0 items-center gap-2.5 overflow-hidden rounded-xl bg-background/70 px-2 py-1.5 text-left shadow-none transition hover:bg-accent/60"
            >
              <.icon name="hero-user-circle" class="size-7 text-muted-foreground shrink-0" />
              <div class="min-w-0 flex-1 overflow-hidden">
                <p class="truncate text-sm font-medium text-foreground">
                  {sidebar_user_label(@current_scope.user)}
                </p>
                <p class="truncate text-xs text-muted-foreground">
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
          },

          updated() {
            this.unbindToggles();
            this.bindToggles();
            this.applyState(this.collapsed ?? this.defaultState(), { persistDesktop: false });
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

  defp organization_active?(membership, %{organization: %{id: organization_id}}) do
    membership.organization_id == organization_id
  end

  defp organization_active?(_membership, _scope), do: false
end
