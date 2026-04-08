defmodule AppWeb.GatewayLive.FormComponent do
  use AppWeb, :live_component

  alias App.Agents
  alias App.Gateways
  alias App.Gateways.Telegram.Webhook, as: TelegramWebhook

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.dialog
        id="gateway-dialog"
        show={true}
        size="md"
        title={@title}
        class="bg-black/55 backdrop-blur-sm sm:rounded-3xl sm:border-border/80 sm:px-6 sm:py-6 sm:shadow-2xl sm:shadow-black/20"
        on_cancel={@on_close}
      >
        <div class="space-y-5 p-1">
          <p class="text-sm text-muted-foreground">
            Connect an external messaging platform to your agents.
          </p>

          <.form
            for={@form}
            id="gateway-form"
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
            class="space-y-5"
          >
            <.input field={@form[:name]} type="text" label="Name" placeholder="My Telegram Bot" />

            <.select
              field={@form[:type]}
              label="Platform"
              options={@type_options}
              placeholder="Select a platform"
            />

            <.input
              field={@form[:token]}
              type="password"
              label="Bot Token"
              placeholder="Enter your bot token"
            />

            <.select
              field={@form[:status]}
              label="Status"
              options={@status_options}
              placeholder="Select status"
            />

            <div class="border-t border-border pt-4">
              <p class="mb-3 text-sm font-medium text-foreground">Channel Configuration</p>

              <.inputs_for :let={config_form} field={@form[:config]}>
                <.select
                  field={config_form[:agent_id]}
                  label="Default Agent"
                  options={@agent_options}
                  placeholder="Select an agent for new channels"
                />

                <div class="mt-4 space-y-2">
                  <input
                    type="hidden"
                    name={config_form[:allow_all_users].name}
                    value="false"
                  />

                  <.checkbox
                    id={config_form[:allow_all_users].id}
                    name={config_form[:allow_all_users].name}
                    value="true"
                    checked={
                      Phoenix.HTML.Form.normalize_value(
                        "checkbox",
                        config_form[:allow_all_users].value
                      )
                    }
                    label="Allow all users to create channels"
                    errors={field_errors(config_form[:allow_all_users])}
                  />
                </div>

                <.input
                  field={config_form[:welcome_message]}
                  type="textarea"
                  label="Welcome Message"
                  placeholder="Welcome! You're now connected."
                />
              </.inputs_for>
            </div>
          </.form>
        </div>
        <:footer>
          <div class="flex justify-end gap-3 pt-2">
            <.button type="button" variant="outline" phx-click={@on_close}>Cancel</.button>
            <.button
              type="button"
              phx-click={JS.dispatch("submit", to: "#gateway-form")}
              phx-disable-with="Saving..."
            >
              Save Gateway
            </.button>
          </div>
        </:footer>
      </.dialog>
    </div>
    """
  end

  @impl true
  def update(%{gateway: gateway} = assigns, socket) do
    changeset = Gateways.change_gateway(gateway)

    agent_options =
      assigns.current_scope
      |> Agents.list_agents()
      |> Enum.sort_by(&String.downcase(&1.name || ""))
      |> Enum.map(fn agent -> {agent.id, agent.name} end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:type_options, type_options())
     |> assign(:status_options, status_options())
     |> assign(:agent_options, [{"", "None"} | agent_options])
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"gateway" => gateway_params}, socket) do
    changeset =
      socket.assigns.gateway
      |> Gateways.change_gateway(gateway_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"gateway" => gateway_params}, socket) do
    save_gateway(socket, socket.assigns.action, gateway_params)
  end

  defp save_gateway(socket, :edit, gateway_params) do
    case Gateways.update_gateway(
           socket.assigns.current_scope,
           socket.assigns.gateway,
           gateway_params
         ) do
      {:ok, gateway} ->
        handle_saved_gateway(socket, gateway, "Gateway updated successfully")

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_gateway(socket, :new, gateway_params) do
    case Gateways.create_gateway(socket.assigns.current_scope, gateway_params) do
      {:ok, gateway} ->
        handle_saved_gateway(socket, gateway, "Gateway created successfully")

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp type_options do
    [
      {"telegram", "Telegram Bot"},
      {"whatsapp_api", "WhatsApp API"}
    ]
  end

  defp status_options do
    [
      {"active", "Active"},
      {"inactive", "Inactive"}
    ]
  end

  defp field_errors(field) do
    if Phoenix.Component.used_input?(field) do
      Enum.map(field.errors, &translate_error/1)
    else
      []
    end
  end

  defp handle_saved_gateway(socket, gateway, success_message) do
    case TelegramWebhook.sync(gateway) do
      {:ok, gateway} ->
        notify_parent({:saved, gateway})

        {:noreply,
         socket
         |> put_flash(:info, success_message)
         |> push_patch(to: ~p"/gateways")}

      {:error, gateway, reason} ->
        notify_parent({:saved, gateway})

        {:noreply,
         socket
         |> put_flash(
           :error,
           "Gateway saved, but Telegram webhook registration failed: #{reason}"
         )
         |> push_patch(to: ~p"/gateways")}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
