defmodule AppWeb.AgentLive.FormComponent do
  use AppWeb, :live_component

  alias App.Agents

  @impl true
  def render(assigns) do
    selected_tools =
      assigns.form[:tools].value
      |> List.wrap()
      |> Enum.reject(&(&1 in [nil, ""]))

    provider_options =
      Enum.map(assigns.providers, fn provider ->
        {provider.id, provider_option_label(provider)}
      end)

    assigns =
      assigns
      |> assign(:selected_tools, selected_tools)
      |> assign(:provider_options, provider_options)
      |> assign_new(:model_options, fn -> [] end)

    ~H"""
    <div>
      <.dialog
        id="agent-dialog"
        show={true}
        size="xl"
        title={@title}
        class="bg-black/55 backdrop-blur-sm sm:rounded-3xl sm:border-border/80 sm:px-6 sm:py-6 sm:shadow-2xl sm:shadow-black/20"
        on_cancel={@on_close}
      >
        <div class="space-y-6 p-1">
          <p class="text-sm text-muted-foreground">
            Configure the agent, its model, and any optional builtin or custom tools.
          </p>

          <%= if @providers == [] do %>
            <div class="space-y-4 rounded-2xl border border-dashed border-border bg-muted/30 p-6 text-center">
              <p class="text-sm text-muted-foreground">
                You need at least one provider before you can create an agent.
              </p>
              <div class="flex justify-center gap-3">
                <.button type="button" variant="outline" phx-click={@on_close}>Close</.button>
                <.link navigate={~p"/providers"}>
                  <.button>Add Provider</.button>
                </.link>
              </div>
            </div>
          <% else %>
            <.form
              for={@form}
              id="agent-form"
              phx-change="validate"
              phx-submit="save"
              phx-target={@myself}
              class="space-y-6"
            >
              <div class="grid gap-4 md:grid-cols-2">
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Name"
                  placeholder="Research Assistant"
                />

                <.select
                  field={@form[:provider_id]}
                  label="Provider"
                  options={@provider_options}
                  placeholder="Select a provider"
                />
              </div>

              <.select
                field={@form[:model]}
                label="Model"
                placeholder="Select a model"
                searchable={true}
                options={@model_options}
              />

              <.textarea
                field={@form[:system_prompt]}
                label="System Prompt"
                rows="6"
                placeholder="You are a helpful assistant focused on concise, practical answers."
              />

              <div class="grid gap-4 md:grid-cols-2">
                <.input
                  field={@form[:temperature]}
                  type="number"
                  label="Temperature"
                  step="0.1"
                  min="0"
                  max="2"
                  placeholder="0.3"
                />

                <.input
                  field={@form[:max_tokens]}
                  type="number"
                  label="Max Tokens"
                  min="1"
                  placeholder="256"
                />
              </div>

              <div class="space-y-3">
                <div>
                  <p class="text-sm font-medium text-foreground">Tools</p>
                  <p class="text-xs text-muted-foreground">
                    Enable builtin tools like `web_fetch` or `shell`, plus any custom API tools you created.
                  </p>
                </div>

                <input type="hidden" name="agent[tools][]" value="" />

                <div class="grid gap-3 md:grid-cols-2">
                  <label
                    :for={tool <- @available_tools}
                    for={"agent-tool-#{tool}"}
                    class={[
                      "flex items-start gap-3 rounded-xl border p-4 transition",
                      if(tool in @selected_tools,
                        do: "border-primary bg-primary/5",
                        else: "border-border hover:border-primary/40"
                      )
                    ]}
                  >
                    <.checkbox
                      id={"agent-tool-#{tool}"}
                      name="agent[tools][]"
                      value={tool}
                      checked={tool in @selected_tools}
                    />
                    <div class="space-y-1">
                      <p class="text-sm font-medium text-foreground">{tool}</p>
                      <p class="text-xs text-muted-foreground">
                        <%= case tool do %>
                          <% "web_fetch" -> %>
                            Fetch and return the body of a web page on demand, with optional headers.
                          <% "shell" -> %>
                            Execute local shell commands and return stdout/stderr. Use with caution.
                          <% _ -> %>
                            Custom API tool created from your saved tool definitions.
                        <% end %>
                      </p>
                    </div>
                  </label>
                </div>
              </div>
            </.form>
          <% end %>
        </div>
        <:footer :if={@providers != []}>
          <div class="flex justify-end gap-3 pt-2">
            <.button type="button" variant="outline" phx-click={@on_close}>Cancel</.button>
            <.button
              type="button"
              phx-click={JS.dispatch("submit", to: "#agent-form")}
              phx-disable-with="Saving..."
            >
              Save Agent
            </.button>
          </div>
        </:footer>
      </.dialog>
    </div>
    """
  end

  @impl true
  def update(%{agent: agent} = assigns, socket) do
    changeset = Agents.change_agent(assigns.current_scope, agent)
    provider_id = Ecto.Changeset.get_field(changeset, :provider_id)
    model_options = model_options_for_provider(provider_id, assigns.providers)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:model_options, model_options)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"agent" => agent_params}, socket) do
    changeset =
      Agents.change_agent(socket.assigns.current_scope, socket.assigns.agent, agent_params)
      |> Map.put(:action, :validate)

    provider_id = Ecto.Changeset.get_field(changeset, :provider_id)
    model_options = model_options_for_provider(provider_id, socket.assigns.providers)

    {:noreply,
     socket
     |> assign(:model_options, model_options)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"agent" => agent_params}, socket) do
    save_agent(socket, socket.assigns.action, agent_params)
  end

  defp save_agent(socket, :edit, agent_params) do
    case Agents.update_agent(socket.assigns.current_scope, socket.assigns.agent, agent_params) do
      {:ok, agent} ->
        notify_parent({:saved, agent})

        {:noreply,
         socket
         |> put_flash(:info, "Agent updated successfully")
         |> push_patch(to: ~p"/agents")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_agent(socket, :new, agent_params) do
    case Agents.create_agent(socket.assigns.current_scope, agent_params) do
      {:ok, agent} ->
        notify_parent({:saved, agent})

        {:noreply,
         socket
         |> put_flash(:info, "Agent created successfully")
         |> push_patch(to: ~p"/agents")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp provider_option_label(provider) do
    case provider.name do
      nil -> String.capitalize(provider.provider)
      name -> "#{name} (#{provider.provider})"
    end
  end

  defp model_options_for_provider(nil, _providers), do: []

  defp model_options_for_provider(provider_id, providers) do
    case Enum.find(providers, &(&1.id == provider_id)) do
      nil ->
        []

      provider ->
        provider_atom = String.to_existing_atom(provider.provider)

        ReqLLM.available_models(scope: provider_atom, api_key: provider.api_key)
    end
  end
end
