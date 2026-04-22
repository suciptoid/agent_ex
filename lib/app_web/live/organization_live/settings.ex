defmodule AppWeb.OrganizationLive.Settings do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Gateways
  alias App.Organizations
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    if Scope.manager?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(:show_add_member_modal?, false)
       |> assign_member_form(Organizations.change_member_form(%{"role" => "member"}))
       |> load_settings()}
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

  def handle_event("delete-mapping", %{"key" => key}, socket) do
    case Gateways.delete_channel_user_mapping(socket.assigns.current_scope, key) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_settings()
         |> put_flash(:info, "Mapping removed successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove mapping")}
    end
  end

  def handle_event("open-add-member-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_member_modal?, true)
     |> assign_member_form(Organizations.change_member_form(%{"role" => "member"}))}
  end

  def handle_event("close-add-member-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_add_member_modal?, false)
     |> assign_member_form(Organizations.change_member_form(%{"role" => "member"}))}
  end

  def handle_event("validate-member", %{"member" => member_params}, socket) do
    changeset =
      member_params
      |> Organizations.change_member_form()
      |> Map.put(:action, :validate)

    {:noreply, assign_member_form(socket, changeset)}
  end

  def handle_event("add-member", %{"member" => member_params}, socket) do
    case Organizations.add_member_by_email(
           socket.assigns.current_scope,
           member_params["email"],
           member_params["role"]
         ) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> assign(:show_add_member_modal?, false)
         |> assign_member_form(Organizations.change_member_form(%{"role" => "member"}))
         |> load_settings()
         |> put_flash(:info, "Member added successfully")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You are not allowed to manage members")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:show_add_member_modal?, true)
         |> assign_member_form(changeset)}
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

            <div class="rounded-3xl border border-border bg-card p-6 shadow-sm sm:p-8">
              <div class="space-y-4">
                <div class="flex items-start justify-between gap-4">
                  <div class="space-y-1">
                    <h2 class="text-lg font-semibold text-foreground">Members</h2>
                    <p class="text-sm text-muted-foreground">
                      Manage who can access this workspace and which role each member has.
                    </p>
                  </div>

                  <.button
                    id="open-add-member-modal-button"
                    phx-click="open-add-member-modal"
                    class="gap-2"
                  >
                    <.icon name="hero-plus" class="size-4" /> Add Member
                  </.button>
                </div>

                <div class="overflow-hidden rounded-xl border border-border">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-border bg-muted/50 text-left text-xs font-medium uppercase tracking-wider text-muted-foreground">
                        <th class="px-4 py-2.5">Member</th>
                        <th class="px-4 py-2.5">Email</th>
                        <th class="px-4 py-2.5">Role</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-border">
                      <%= for membership <- @memberships do %>
                        <tr class="transition-colors hover:bg-muted/30">
                          <td class="px-4 py-2.5">
                            <div class="font-medium text-foreground">
                              {membership.user.name || "Unnamed"}
                            </div>
                          </td>
                          <td class="px-4 py-2.5 text-muted-foreground">
                            {membership.user.email}
                          </td>
                          <td class="px-4 py-2.5">
                            <span class="inline-flex items-center rounded-full border border-border bg-muted/70 px-2.5 py-1 text-xs font-medium capitalize text-foreground">
                              {membership.role}
                            </span>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <div class="rounded-3xl border border-border bg-card p-6 shadow-sm sm:p-8">
              <div class="space-y-4">
                <div class="space-y-1">
                  <h2 class="text-lg font-semibold text-foreground">Channel User Mappings</h2>
                  <p class="text-sm text-muted-foreground">
                    Manage how external users from gateway channels are mapped to organization users.
                    These mappings determine whether incoming channel messages are processed automatically.
                  </p>
                </div>

                <%= if @channel_user_mappings == [] do %>
                  <p class="text-sm text-muted-foreground/60">
                    No user mappings configured yet. Mappings are created automatically when you approve a pending channel in a chat room.
                  </p>
                <% else %>
                  <div class="overflow-hidden rounded-xl border border-border">
                    <table class="w-full text-sm">
                      <thead>
                        <tr class="border-b border-border bg-muted/50 text-left text-xs font-medium uppercase tracking-wider text-muted-foreground">
                          <th class="px-4 py-2.5">Gateway</th>
                          <th class="px-4 py-2.5">External User ID</th>
                          <th class="px-4 py-2.5">Mapped User</th>
                          <th class="px-4 py-2.5 text-right">Actions</th>
                        </tr>
                      </thead>
                      <tbody class="divide-y divide-border">
                        <%= for mapping <- @channel_user_mappings do %>
                          <tr class="transition-colors hover:bg-muted/30">
                            <td class="px-4 py-2.5 capitalize text-foreground">
                              {mapping.gateway_type}
                            </td>
                            <td class="px-4 py-2.5 font-mono text-xs text-muted-foreground">
                              {mapping.external_user_id}
                            </td>
                            <td class="px-4 py-2.5 text-foreground">
                              {mapping.user_label}
                            </td>
                            <td class="px-4 py-2.5 text-right">
                              <button
                                type="button"
                                phx-click="delete-mapping"
                                phx-value-key={mapping.key}
                                data-confirm="Remove this user mapping?"
                                class="inline-flex size-7 items-center justify-center rounded-md text-muted-foreground transition hover:bg-destructive/10 hover:text-destructive"
                                title="Remove mapping"
                              >
                                <.icon name="hero-trash" class="size-4" />
                              </button>
                            </td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                <% end %>
              </div>
            </div>
          </section>
        </div>
      </div>

      <.dialog
        id="organization-member-dialog"
        show={@show_add_member_modal?}
        size="md"
        title="Add member"
        class="bg-black/55 backdrop-blur-sm sm:rounded-3xl sm:border-border/80 sm:px-6 sm:py-6 sm:shadow-2xl sm:shadow-black/20"
        on_cancel={JS.push("close-add-member-modal")}
      >
        <div class="space-y-5 p-1">
          <p class="text-sm text-muted-foreground">
            Add an existing registered user to this organization and choose their role.
          </p>

          <.form
            for={@member_form}
            id="organization-member-form"
            phx-change="validate-member"
            phx-submit="add-member"
            class="space-y-5"
          >
            <.input
              field={@member_form[:email]}
              type="email"
              label="User email"
              placeholder="teammate@example.com"
            />

            <.select
              field={@member_form[:role]}
              label="Role"
              options={@member_role_options}
              placeholder="Select a role"
            />
          </.form>
        </div>
        <:footer>
          <div class="flex justify-end gap-3 pt-2">
            <.button type="button" variant="outline" phx-click="close-add-member-modal">
              Cancel
            </.button>
            <.button
              id="save-organization-member-button"
              type="button"
              phx-click={JS.dispatch("submit", to: "#organization-member-form")}
              phx-disable-with="Adding..."
            >
              Add Member
            </.button>
          </div>
        </:footer>
      </.dialog>
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

    memberships = Organizations.list_organization_members(current_scope)

    mappings =
      current_scope
      |> Gateways.list_channel_user_mappings()
      |> decorate_channel_user_mappings(memberships)

    socket
    |> assign(:effective_default_agent, effective_default_agent)
    |> assign(:agent_options, [{"", "Newest created agent (fallback)"} | agent_options])
    |> assign(:member_role_options, member_role_options())
    |> assign(:memberships, memberships)
    |> assign(:channel_user_mappings, mappings)
    |> assign_form(changeset)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :settings))
  end

  defp assign_member_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :member_form, to_form(changeset, as: :member))
  end

  defp decorate_channel_user_mappings(mappings, memberships) do
    members_by_id =
      Map.new(memberships, fn membership ->
        {membership.user_id, member_label(membership.user)}
      end)

    Enum.map(mappings, fn mapping ->
      Map.put(mapping, :user_label, Map.get(members_by_id, mapping.user_id, mapping.user_id))
    end)
  end

  defp member_label(user) do
    case {user.name, user.email} do
      {name, email} when is_binary(name) and name != "" and is_binary(email) and email != "" ->
        "#{name} (#{email})"

      {_name, email} when is_binary(email) and email != "" ->
        email

      {name, _email} when is_binary(name) and name != "" ->
        name

      _other ->
        "Unnamed"
    end
  end

  defp member_role_options do
    Enum.map(App.Organizations.Membership.roles(), fn role ->
      {role, String.capitalize(role)}
    end)
  end

  defp effective_default_label(nil), do: "No agents available"
  defp effective_default_label(agent), do: agent.name
end
