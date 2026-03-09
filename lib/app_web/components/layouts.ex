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
end
