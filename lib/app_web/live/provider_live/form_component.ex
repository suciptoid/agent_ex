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
        variant="unstyled"
        class="fixed inset-0 z-50 bg-black/55 backdrop-blur-sm"
        on_cancel={@on_close}
      >
        <:content :let={{attrs, %{hide: hide}}}>
          <.focus_wrap {attrs}>
            <div
              role="dialog"
              aria-modal="true"
              class="fixed inset-0 z-50 flex items-center justify-center p-4"
            >
            <div class="w-full max-w-md rounded-3xl border border-border/80 bg-background p-6 shadow-2xl shadow-black/20 sm:p-7">
              <div class="mb-6 space-y-2">
                <h2 class="text-2xl font-semibold text-foreground">{@title}</h2>
                <p class="text-sm text-muted-foreground">
                  Save your provider details securely so agents can reuse them across rooms.
                </p>
              </div>

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
                  options={[
                    {"openai", "OpenAI"},
                    {"anthropic", "Anthropic"},
                    {"google", "Google"},
                    {"gemini", "Gemini"},
                    {"mistral", "Mistral"},
                    {"cohere", "Cohere"},
                    {"openrouter", "OpenRouter"}
                  ]}
                  placeholder="Select a provider"
                />

                <.input field={@form[:api_key]} type="password" label="API Key" />

                <div class="flex justify-end gap-3 pt-2">
                  <.button type="button" variant="outline" phx-click={hide}>Cancel</.button>
                  <.button type="submit" phx-disable-with="Saving...">Save Provider</.button>
                </div>
              </.form>
            </div>
          </div>
          </.focus_wrap>
        </:content>
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
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
