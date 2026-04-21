defmodule AppWeb.OrganizationLive.Settings do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Organizations
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    if Scope.manager?(socket.assigns.current_scope) do
      {:ok, load_settings(socket)}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         "Only organization owners and admins can manage organization settings."
       )
       |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Organization Settings")}
  end

  @impl true
  def handle_event("validate", %{"settings" => settings_params}, socket) do
    changeset =
      socket.assigns.current_scope
      |> Organizations.change_settings(settings_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"settings" => settings_params}, socket) do
    case Organizations.update_settings(socket.assigns.current_scope, settings_params) do
      {:ok, _default_agent_id} ->
        {:noreply,
         socket
         |> load_settings()
         |> put_flash(:info, "Organization settings updated successfully")}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Only organization owners and admins can manage organization settings."
         )
         |> push_navigate(to: ~p"/dashboard")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
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
        <div id="organization-settings-page" class="mx-auto w-full max-w-4xl">
          <section class="space-y-6">
            <div class="space-y-3 border-b border-border pb-6">
              <div class="space-y-2">
                <h1 class="text-3xl font-bold tracking-tight text-foreground">
                  Organization Settings
                </h1>
                <p class="max-w-2xl text-sm leading-6 text-muted-foreground">
                  Configure workspace-wide defaults for new conversations and future organization-level settings.
                </p>
              </div>
            </div>

            <div class="rounded-3xl border border-border bg-card p-6 shadow-sm sm:p-8">
              <div class="space-y-6">
                <div class="rounded-2xl border border-primary/10 bg-primary/5 px-4 py-3 text-sm text-primary">
                  <strong class="font-semibold">Current effective default agent:</strong>
                  <span class="ml-1">{effective_default_label(@effective_default_agent)}</span>
                </div>

                <.form
                  for={@form}
                  id="organization-settings-form"
                  phx-change="validate"
                  phx-submit="save"
                  class="space-y-5"
                >
                  <.select
                    field={@form[:default_agent_id]}
                    label="Default Agent"
                    options={@agent_options}
                    placeholder="Choose the default agent for new chats"
                  />

                  <p class="text-xs leading-5 text-muted-foreground">
                    Leave this unset to fall back to the newest created agent in the organization.
                  </p>

                  <div class="flex justify-end gap-3 border-t border-border pt-6">
                    <.button
                      id="save-organization-settings-button"
                      type="submit"
                      phx-disable-with="Saving..."
                    >
                      Save Settings
                    </.button>
                  </div>
                </.form>
              </div>
            </div>
          </section>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end

  defp load_settings(socket) do
    current_scope = socket.assigns.current_scope
    effective_default_agent = Organizations.default_agent(current_scope)
    changeset = Organizations.change_settings(current_scope)

    agent_options =
      current_scope
      |> Agents.list_agents()
      |> Enum.sort_by(&String.downcase(&1.name || ""))
      |> Enum.map(fn agent -> {agent.id, agent.name} end)

    socket
    |> assign(:effective_default_agent, effective_default_agent)
    |> assign(:agent_options, [{"", "Newest created agent (fallback)"} | agent_options])
    |> assign_form(changeset)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :settings))
  end

  defp effective_default_label(nil), do: "No agents available"
  defp effective_default_label(agent), do: agent.name
end
