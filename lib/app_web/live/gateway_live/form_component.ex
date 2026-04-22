defmodule AppWeb.GatewayLive.FormComponent do
  use AppWeb, :live_component

  alias App.Agents
  alias App.Gateways
  alias App.Gateways.Telegram.Webhook, as: TelegramWebhook
  alias App.Organizations

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:display_mode, fn -> :dialog end)
      |> assign_new(:navigation, fn -> :patch end)
      |> assign_new(:return_to, fn -> ~p"/gateways" end)

    ~H"""
    <div>
      <%= if @display_mode == :page do %>
        <div
          id="gateway-form-card"
          class="rounded-3xl border border-border bg-card p-6 shadow-sm sm:p-8"
        >
          <div class="space-y-6">
            <.form_content
              form={@form}
              type_options={@type_options}
              status_options={@status_options}
              update_mode_options={@update_mode_options}
              agent_options={@agent_options}
              target={@myself}
            />

            <div class="flex justify-end gap-3 border-t border-border pt-6">
              <.link navigate={@return_to}>
                <.button type="button" variant="outline">Cancel</.button>
              </.link>
              <.button
                id="save-gateway-button"
                type="button"
                phx-click={JS.dispatch("submit", to: "#gateway-form")}
                phx-disable-with="Saving..."
              >
                {save_label(@action)}
              </.button>
            </div>
          </div>
        </div>
      <% else %>
        <.dialog
          id="gateway-dialog"
          show={true}
          size="md"
          title={@title}
          class="bg-black/55 backdrop-blur-sm sm:rounded-3xl sm:border-border/80 sm:px-6 sm:py-6 sm:shadow-2xl sm:shadow-black/20"
          on_cancel={@on_close}
        >
          <div class="space-y-5 p-1">
            <.form_content
              form={@form}
              type_options={@type_options}
              status_options={@status_options}
              update_mode_options={@update_mode_options}
              agent_options={@agent_options}
              target={@myself}
            />
          </div>
          <:footer>
            <div class="flex justify-end gap-3 pt-2">
              <.button type="button" variant="outline" phx-click={@on_close}>Cancel</.button>
              <.button
                id="save-gateway-button"
                type="button"
                phx-click={JS.dispatch("submit", to: "#gateway-form")}
                phx-disable-with="Saving..."
              >
                {save_label(@action)}
              </.button>
            </div>
          </:footer>
        </.dialog>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(%{gateway: gateway} = assigns, socket) do
    default_agent = Organizations.default_agent(assigns.current_scope)
    changeset = Gateways.change_gateway(gateway, default_gateway_attrs(gateway, default_agent))

    agent_options =
      assigns.current_scope
      |> Agents.list_agents()
      |> Enum.sort_by(&String.downcase(&1.name || ""))
      |> Enum.map(fn agent -> {agent.id, agent.name} end)

    {:ok,
     socket
     |> assign_new(:display_mode, fn -> :dialog end)
     |> assign_new(:navigation, fn -> :patch end)
     |> assign_new(:return_to, fn -> ~p"/gateways" end)
     |> assign(assigns)
     |> assign(:type_options, type_options())
     |> assign(:status_options, status_options())
     |> assign(:update_mode_options, update_mode_options())
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

  attr :form, :any, required: true
  attr :type_options, :list, required: true
  attr :status_options, :list, required: true
  attr :update_mode_options, :list, required: true
  attr :agent_options, :list, required: true
  attr :target, :any, required: true

  defp form_content(assigns) do
    ~H"""
    <div class="space-y-5">
      <p class="text-sm text-muted-foreground">
        Connect an external messaging platform to your agents.
      </p>

      <div class="rounded-2xl border border-sky-500/20 bg-sky-500/5 px-4 py-3 text-sm text-sky-900 dark:text-sky-100">
        Telegram groups:
        disable BotFather privacy mode or make the bot an admin if you want normal group messages to reach this gateway.
        With privacy mode enabled, Telegram only forwards limited bot-relevant messages such as commands and replies.
      </div>

      <.form
        for={@form}
        id="gateway-form"
        phx-change="validate"
        phx-submit="save"
        phx-target={@target}
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
            <div class="space-y-3 rounded-2xl border border-border bg-muted/20 p-4">
              <div class="space-y-1">
                <p class="text-sm font-medium text-foreground">Assigned Agents</p>
                <p class="text-xs leading-5 text-muted-foreground">
                  New gateway chat rooms will include each selected agent. The default agent becomes the active responder for the first turn.
                </p>
              </div>

              <input type="hidden" name={config_form[:agent_ids].name <> "[]"} value="" />

              <div class="grid gap-2 sm:grid-cols-2">
                <label
                  :for={
                    {agent_id, agent_name} <-
                      Enum.reject(@agent_options, fn {id, _name} -> id == "" end)
                  }
                  class="flex items-start gap-3 rounded-xl border border-border bg-background px-3 py-3 text-sm transition hover:border-primary/30 hover:bg-accent/10"
                >
                  <input
                    type="checkbox"
                    name={config_form[:agent_ids].name <> "[]"}
                    value={agent_id}
                    checked={agent_selected?(config_form[:agent_ids].value, agent_id)}
                    class="mt-0.5 size-4 rounded border-border text-primary focus:ring-primary"
                  />
                  <span class="min-w-0">
                    <span class="block truncate font-medium text-foreground">{agent_name}</span>
                    <span class="block text-xs text-muted-foreground">
                      Available for new gateway conversations
                    </span>
                  </span>
                </label>
              </div>
            </div>

            <.select
              field={config_form[:agent_id]}
              label="Default Active Agent"
              options={@agent_options}
              placeholder="Select the active agent for new channels"
            />

            <%= if telegram_gateway?(@form[:type].value) do %>
              <.select
                field={config_form[:update_mode]}
                label="Telegram Update Mode"
                options={@update_mode_options}
                placeholder="Select how Telegram delivers updates"
              />

              <p class="text-xs leading-5 text-muted-foreground">
                Webhook is the default and recommended when this app is publicly reachable.
                Long polling uses Telegram's getUpdates API from a supervised background worker.
              </p>
            <% end %>

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
    """
  end

  defp handle_saved_gateway(socket, gateway, success_message) do
    case TelegramWebhook.sync(gateway) do
      {:ok, gateway} ->
        notify_parent({:saved, gateway})

        {:noreply,
         socket
         |> put_flash(:info, success_message)
         |> navigate_after_save()}

      {:error, gateway, reason} ->
        notify_parent({:saved, gateway})

        {:noreply,
         socket
         |> put_flash(
           :error,
           "Gateway saved, but Telegram update sync failed: #{reason}"
         )
         |> navigate_after_save()}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp navigate_after_save(%{assigns: %{navigation: :navigate, return_to: return_to}} = socket) do
    push_navigate(socket, to: return_to)
  end

  defp navigate_after_save(%{assigns: %{return_to: return_to}} = socket) do
    push_patch(socket, to: return_to)
  end

  defp default_gateway_attrs(%{id: nil, config: nil}, nil), do: %{}

  defp default_gateway_attrs(%{id: nil, config: nil}, default_agent) do
    %{
      "config" => %{
        "agent_id" => default_agent.id,
        "agent_ids" => [default_agent.id]
      }
    }
  end

  defp default_gateway_attrs(_gateway, _default_agent), do: %{}

  defp agent_selected?(value, agent_id) when is_list(value), do: agent_id in value
  defp agent_selected?(_value, _agent_id), do: false

  defp telegram_gateway?(value), do: to_string(value) == "telegram"

  defp update_mode_options do
    [
      {"webhook", "Webhook"},
      {"longpoll", "Long Polling"}
    ]
  end

  defp save_label(:edit), do: "Save Changes"
  defp save_label(_action), do: "Save Gateway"
end
