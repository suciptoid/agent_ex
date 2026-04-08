defmodule AppWeb.ProviderLive.Index do
  use AppWeb, :live_view

  alias App.Providers
  alias App.Providers.Provider
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage_organization?, Scope.manager?(socket.assigns.current_scope))
     |> stream(:providers, Providers.list_providers(socket.assigns.current_scope))}
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
    if socket.assigns.can_manage_organization? do
      socket
      |> assign(:page_title, "New Provider")
      |> assign(:provider, %Provider{})
    else
      socket
      |> put_flash(:error, "Only organization owners and admins can manage providers.")
      |> push_patch(to: ~p"/providers")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    cond do
      not socket.assigns.can_manage_organization? ->
        socket
        |> put_flash(:error, "Only organization owners and admins can manage providers.")
        |> push_patch(to: ~p"/providers")

      provider = Providers.get_provider(socket.assigns.current_scope, id) ->
        socket
        |> assign(:page_title, "Edit Provider")
        |> assign(:provider, provider)

      provider = Providers.get_provider_for_user(socket.assigns.current_scope.user, id) ->
        redirect(
          socket,
          to: switch_path(provider.organization_id, ~p"/providers/#{id}/edit")
        )

      true ->
        raise Ecto.NoResultsError, query: Provider
    end
  end

  @impl true
  def handle_info({AppWeb.ProviderLive.FormComponent, {:saved, provider}}, socket) do
    {:noreply, stream_insert(socket, :providers, provider)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if socket.assigns.can_manage_organization? do
      provider = Providers.get_provider!(socket.assigns.current_scope, id)
      {:ok, _} = Providers.delete_provider(socket.assigns.current_scope, provider)

      {:noreply, stream_delete(socket, :providers, provider)}
    else
      {:noreply,
       put_flash(socket, :error, "Only organization owners and admins can manage providers.")}
    end
  end

  defp switch_path(organization_id, return_to) do
    ~p"/organizations/switch/#{organization_id}?return_to=#{return_to}"
  end
end
