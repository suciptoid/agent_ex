defmodule AppWeb.GatewayLive.Form do
  use AppWeb, :live_view

  alias App.Gateways
  alias App.Gateways.Gateway
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    if Scope.manager?(socket.assigns.current_scope) do
      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only organization owners and admins can manage gateways.")
       |> push_navigate(to: ~p"/gateways")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_info({AppWeb.GatewayLive.FormComponent, {:saved, _gateway}}, socket) do
    {:noreply, socket}
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
        <div id="gateway-form-page" class="mx-auto w-full max-w-4xl">
          <section class="space-y-6">
            <div class="space-y-3 border-b border-border pb-6">
              <.link
                navigate={~p"/gateways"}
                class="inline-flex w-fit items-center gap-2 text-sm text-muted-foreground transition hover:text-foreground"
              >
                <.icon name="hero-arrow-left" class="size-4" />
                <span>Back to gateways</span>
              </.link>

              <div class="space-y-2">
                <h1 class="text-3xl font-bold tracking-tight text-foreground">{@page_title}</h1>
                <p class="text-sm text-muted-foreground">
                  Configure the platform, webhook token, and default channel behavior for both private and group conversations.
                </p>
              </div>
            </div>

            <.live_component
              module={AppWeb.GatewayLive.FormComponent}
              id={if(@gateway.id, do: @gateway.id, else: "new-gateway")}
              title={@page_title}
              action={@live_action}
              gateway={@gateway}
              current_scope={@current_scope}
              display_mode={:page}
              navigation={:navigate}
              return_to={~p"/gateways"}
            />
          </section>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Gateway")
    |> assign(:gateway, %Gateway{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Gateway")
    |> assign(:gateway, Gateways.get_gateway!(socket.assigns.current_scope, id))
  end
end
