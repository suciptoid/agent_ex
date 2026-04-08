defmodule AppWeb.ProviderLive.FormComponent do
  use AppWeb, :live_component

  alias App.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.dialog
        id="provider-dialog"
        show={true}
        size="md"
        title={@title}
        class="bg-black/55 backdrop-blur-sm sm:rounded-3xl sm:border-border/80 sm:px-6 sm:py-6 sm:shadow-2xl sm:shadow-black/20"
        on_cancel={@on_close}
      >
        <div class="space-y-5 p-1">
          <p class="text-sm text-muted-foreground">
            Save your provider details securely so agents can reuse them across rooms.
          </p>

          <.form
            for={@form}
            id="provider-form"
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
            class="space-y-5"
          >
            <.input field={@form[:name]} type="text" label="Name (optional)" />

            <.select
              field={@form[:provider]}
              label="Provider"
              options={@provider_options}
              searchable={true}
              placeholder="Select a provider"
            />

            <.input field={@form[:api_key]} type="password" label="API Key" />
          </.form>
        </div>
        <:footer>
          <div class="flex justify-end gap-3 pt-2">
            <.button type="button" variant="outline" phx-click={@on_close}>Cancel</.button>
            <.button
              type="button"
              phx-click={JS.dispatch("submit", to: "#provider-form")}
              phx-disable-with="Saving..."
            >
              Save Provider
            </.button>
          </div>
        </:footer>
      </.dialog>
    </div>
    """
  end

  @impl true
  def update(%{provider: provider} = assigns, socket) do
    changeset = Providers.change_provider(provider)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:provider_options, Providers.provider_options())
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"provider" => provider_params}, socket) do
    changeset =
      socket.assigns.provider
      |> Providers.change_provider(provider_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"provider" => provider_params}, socket) do
    save_provider(socket, socket.assigns.action, provider_params)
  end

  defp save_provider(socket, :edit, provider_params) do
    case Providers.update_provider(
           socket.assigns.current_scope,
           socket.assigns.provider,
           provider_params
         ) do
      {:ok, provider} ->
        notify_parent({:saved, provider})

        {:noreply,
         socket
         |> put_flash(:info, "Provider updated successfully")
         |> push_patch(to: ~p"/providers")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, "Only organization owners and admins can manage providers.")
         |> push_patch(to: ~p"/providers")}
    end
  end

  defp save_provider(socket, :new, provider_params) do
    case Providers.create_provider(socket.assigns.current_scope, provider_params) do
      {:ok, provider} ->
        notify_parent({:saved, provider})

        {:noreply,
         socket
         |> put_flash(:info, "Provider created successfully")
         |> push_patch(to: ~p"/providers")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, "Only organization owners and admins can manage providers.")
         |> push_patch(to: ~p"/providers")}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
