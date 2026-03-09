defmodule AppWeb.ProviderLive.Index do
  use AppWeb, :live_view

  alias App.Providers
  alias App.Providers.Provider

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :providers, Providers.list_providers(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Providers")
    |> assign(:provider, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Provider")
    |> assign(:provider, %Provider{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    provider = Providers.get_provider!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Provider")
    |> assign(:provider, provider)
  end

  @impl true
  def handle_info({AppWeb.ProviderLive.FormComponent, {:saved, provider}}, socket) do
    {:noreply, stream_insert(socket, :providers, provider)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    provider = Providers.get_provider!(socket.assigns.current_scope, id)
    {:ok, _} = Providers.delete_provider(socket.assigns.current_scope, provider)

    {:noreply, stream_delete(socket, :providers, provider)}
  end
end
