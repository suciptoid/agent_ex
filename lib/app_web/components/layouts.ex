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
    <div class="relative flex flex-row items-center border-2 border-gray-300 dark:border-gray-600 bg-gray-200 dark:bg-gray-700 rounded-full p-1">
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

  ## Examples

      <Layouts.dashboard flash={@flash} current_scope={@current_scope} sidebar_collapsed={@sidebar_collapsed}>
        <h1>Dashboard Content</h1>
      </Layouts.dashboard>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :sidebar_collapsed, :boolean, default: true, doc: "whether sidebar is collapsed"

  slot :inner_block, required: true

  def dashboard(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
      <%!-- Header --%>
      <header class="fixed top-0 left-0 right-0 z-30 flex items-center justify-between px-4 py-3 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
        <div class="flex items-center gap-4">
          <button
            type="button"
            phx-click="toggle_sidebar"
            class="p-2 rounded-lg text-gray-500 hover:text-gray-700 hover:bg-gray-100 dark:text-gray-400 dark:hover:text-gray-200 dark:hover:bg-gray-700"
            aria-label={if @sidebar_collapsed, do: "Expand sidebar", else: "Collapse sidebar"}
          >
            <.icon name="hero-bars-3" class="size-6" />
          </button>
          <a href="/" class="flex items-center gap-2">
            <img src={~p"/images/logo.svg"} width="32" />
            <span class="text-lg font-semibold text-gray-900 dark:text-white hidden sm:block">
              App
            </span>
          </a>
        </div>

        <div class="flex items-center gap-4">
          <.theme_toggle />
          <div class="relative group">
            <button
              type="button"
              class="flex items-center gap-2 p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700"
              aria-haspopup="true"
            >
              <.icon name="hero-user-circle" class="size-6 text-gray-500 dark:text-gray-400" />
              <span class="hidden sm:block text-sm text-gray-700 dark:text-gray-300 max-w-[150px] truncate">
                {@current_scope.user.email}
              </span>
              <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
            </button>

            <%!-- Dropdown Menu --%>
            <div class="absolute right-0 mt-1 w-48 py-1 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200">
              <.link
                navigate={~p"/users/settings"}
                class="flex items-center gap-2 px-4 py-2 text-sm text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"
              >
                <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
              </.link>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="flex items-center gap-2 px-4 py-2 text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
              </.link>
            </div>
          </div>
        </div>
      </header>

      <%!-- Sidebar Overlay (for mobile when expanded) --%>
      <div
        phx-click="toggle_sidebar"
        class={[
          "fixed inset-0 bg-black/50 z-20 transition-opacity duration-300 lg:hidden",
          @sidebar_collapsed && "opacity-0 pointer-events-none",
          !@sidebar_collapsed && "opacity-100"
        ]}
      />

      <%!-- Sidebar --%>
      <aside class={[
        "fixed top-0 left-0 z-30 h-full pt-16 bg-gray-900 dark:bg-gray-950 transition-transform duration-300 ease-in-out",
        @sidebar_collapsed && "-translate-x-full",
        !@sidebar_collapsed && "translate-x-0",
        "w-64"
      ]}>
        <div class="flex flex-col h-full">
          <%!-- Navigation Links --%>
          <nav class="flex-1 px-3 py-4 space-y-1 overflow-y-auto">
            <.link
              navigate={~p"/dashboard"}
              class="flex items-center gap-3 px-3 py-2 text-sm font-medium text-white rounded-lg hover:bg-gray-800"
            >
              <.icon name="hero-home" class="size-5" /> Dashboard
            </.link>

            <.link
              navigate={~p"/users/settings"}
              class="flex items-center gap-3 px-3 py-2 text-sm font-medium text-gray-300 rounded-lg hover:bg-gray-800 hover:text-white"
            >
              <.icon name="hero-cog-6-tooth" class="size-5" /> Settings
            </.link>
          </nav>

          <%!-- User Section (Bottom) --%>
          <div class="p-4 border-t border-gray-800">
            <div class="flex items-center gap-3">
              <.icon name="hero-user-circle" class="size-10 text-gray-400" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-white truncate">
                  {@current_scope.user.email}
                </p>
                <p class="text-xs text-gray-400 truncate">User</p>
              </div>
            </div>
          </div>
        </div>
      </aside>

      <%!-- Main Content --%>
      <main class={[
        "pt-16 transition-all duration-300 ease-in-out min-h-screen",
        @sidebar_collapsed && "lg:ml-0",
        !@sidebar_collapsed && "lg:ml-64"
      ]}>
        <div class="p-4 sm:p-6 lg:p-8 max-w-7xl mx-auto">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end
end
