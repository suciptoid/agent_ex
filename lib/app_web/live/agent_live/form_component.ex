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

    ~H"""
    <div>
      <.dialog
        id="agent-dialog"
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
              <div class="w-full max-w-2xl rounded-3xl border border-border/80 bg-background p-6 shadow-2xl shadow-black/20 sm:p-7">
                <div class="mb-6 space-y-2">
                  <h2 class="text-2xl font-semibold text-foreground">{@title}</h2>
                  <p class="text-sm text-muted-foreground">
                    Configure the agent, its model, and any optional builtin tools.
                  </p>
                </div>

                <%= if @providers == [] do %>
                  <div class="space-y-4 rounded-2xl border border-dashed border-border bg-muted/30 p-6 text-center">
                    <p class="text-sm text-muted-foreground">
                      You need at least one provider before you can create an agent.
                    </p>
                    <div class="flex justify-center gap-3">
                      <.button type="button" variant="outline" phx-click={hide}>Close</.button>
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

                    <.input
                      field={@form[:model]}
                      type="text"
                      label="Model"
                      placeholder="anthropic:claude-haiku-4-5"
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
                        <p class="text-sm font-medium text-foreground">Builtin Tools</p>
                        <p class="text-xs text-muted-foreground">
                          Enable optional capabilities the model can call while generating a response.
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
                                  Fetch and return the body of a web page on demand.
                                <% _ -> %>
                                  Additional tool support.
                              <% end %>
                            </p>
                          </div>
                        </label>
                      </div>
                    </div>

                    <div class="flex justify-end gap-3 pt-2">
                      <.button type="button" variant="outline" phx-click={hide}>Cancel</.button>
                      <.button type="submit" phx-disable-with="Saving...">Save Agent</.button>
                    </div>
                  </.form>
                <% end %>
              </div>
            </div>
          </.focus_wrap>
        </:content>
      </.dialog>
    </div>
    """
  end

  @impl true
  def update(%{agent: agent} = assigns, socket) do
    changeset = Agents.change_agent(agent)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"agent" => agent_params}, socket) do
    changeset =
      socket.assigns.agent
      |> Agents.change_agent(agent_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
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
end
