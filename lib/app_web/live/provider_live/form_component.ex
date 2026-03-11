defmodule AppWeb.ProviderLive.FormComponent do
  use AppWeb, :live_component

  alias App.Providers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div class="w-full max-w-md p-6 bg-white rounded-lg shadow-xl dark:bg-gray-800">
        <div class="mb-6">
          <h2 class="text-xl font-semibold text-gray-900 dark:text-white">{@title}</h2>
        </div>

        <.form
          for={@form}
          id="provider-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
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

          <div class="flex justify-end gap-3 mt-6">
            <.button type="button" variant="outline" phx-click={@on_close}>Cancel</.button>
            <.button type="submit" phx-disable-with="Saving...">Save Provider</.button>
          </div>
        </.form>
      </div>
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
