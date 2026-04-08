defmodule AppWeb.OrganizationLive.Select do
  use AppWeb, :live_view

  alias App.Organizations
  alias App.Organizations.Organization

  @impl true
  def mount(_params, session, socket) do
    memberships = Organizations.list_memberships(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:page_title, "Select Organization")
     |> assign(:memberships, memberships)
     |> assign(:return_to, session["organization_return_to"] || ~p"/dashboard")
     |> assign(:show_create_modal?, memberships == [])
     |> assign_form(Organizations.change_organization(%Organization{}))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    show_create_modal? = params["new"] == "true" || socket.assigns.memberships == []
    {:noreply, assign(socket, :show_create_modal?, show_create_modal?)}
  end

  @impl true
  def handle_event("open-create-modal", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/organizations/select?new=true")}
  end

  def handle_event("close-create-modal", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/organizations/select")}
  end

  def handle_event("validate", %{"organization" => organization_params}, socket) do
    changeset =
      %Organization{}
      |> Organizations.change_organization(organization_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"organization" => organization_params}, socket) do
    case Organizations.create_organization(socket.assigns.current_scope.user, organization_params) do
      {:ok, organization} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization created successfully")
         |> redirect(to: switch_path(organization.id, socket.assigns.return_to))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-4xl space-y-8 py-8">
        <section class="overflow-hidden rounded-3xl border border-border bg-gradient-to-br from-card via-card to-primary/5 p-8 shadow-sm">
          <div class="flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
            <div class="space-y-3">
              <div class="inline-flex items-center gap-2 rounded-full border border-primary/15 bg-primary/5 px-3 py-1 text-xs font-medium text-primary">
                <.icon name="hero-building-office-2" class="size-3.5" />
                <span>Workspace selection</span>
              </div>

              <div class="space-y-2">
                <h1 class="text-3xl font-bold tracking-tight text-foreground">
                  Choose your organization
                </h1>
                <p class="max-w-2xl text-sm leading-6 text-muted-foreground">
                  Organizations group providers, tools, agents, and chat rooms into a shared workspace. Pick one to continue, or create a new organization to start fresh.
                </p>
              </div>
            </div>

            <.button id="new-organization-button" phx-click="open-create-modal" class="gap-2">
              <.icon name="hero-plus" class="size-4" /> Create New Organization
            </.button>
          </div>
        </section>

        <section class="space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold text-foreground">Available workspaces</h2>
            <span class="text-sm text-muted-foreground">{length(@memberships)} organizations</span>
          </div>

          <%= if @memberships == [] do %>
            <div class="rounded-3xl border border-dashed border-border bg-muted/30 p-10 text-center">
              <div class="mx-auto flex size-16 items-center justify-center rounded-2xl bg-primary/10 text-primary">
                <.icon name="hero-building-office-2" class="size-8" />
              </div>
              <h3 class="mt-5 text-lg font-semibold text-foreground">
                Create your first organization
              </h3>
              <p class="mx-auto mt-2 max-w-lg text-sm leading-6 text-muted-foreground">
                Your first organization becomes the workspace for your providers, agents, tools, and conversations.
              </p>
            </div>
          <% else %>
            <div class="grid gap-4 md:grid-cols-2">
              <.link
                :for={membership <- @memberships}
                id={"organization-card-#{membership.organization_id}"}
                href={switch_path(membership.organization_id, @return_to)}
                class="group rounded-3xl border border-border bg-card p-6 shadow-sm transition hover:border-primary/30 hover:bg-accent/10"
              >
                <div class="flex items-start justify-between gap-4">
                  <div class="space-y-2">
                    <div class="flex items-center gap-3">
                      <div class="flex size-11 items-center justify-center rounded-2xl bg-primary/10 text-primary transition group-hover:bg-primary group-hover:text-primary-foreground">
                        <.icon name="hero-building-office-2" class="size-5" />
                      </div>
                      <div>
                        <p class="text-lg font-semibold text-foreground">
                          {membership.organization.name}
                        </p>
                        <p class="text-sm text-muted-foreground">
                          {organization_role_label(membership.role)}
                        </p>
                      </div>
                    </div>

                    <div class="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                      <span class="inline-flex items-center rounded-full border border-border bg-muted/60 px-2.5 py-1 font-medium text-foreground">
                        {String.capitalize(membership.role)}
                      </span>

                      <span
                        :if={active_organization?(membership, @current_scope)}
                        class="inline-flex items-center gap-1 rounded-full border border-primary/20 bg-primary/10 px-2.5 py-1 font-medium text-primary"
                      >
                        <.icon name="hero-check" class="size-3.5" /> Current
                      </span>
                    </div>
                  </div>

                  <span class="inline-flex size-10 items-center justify-center rounded-full bg-muted text-muted-foreground transition group-hover:bg-primary/10 group-hover:text-primary">
                    <.icon name="hero-arrow-right" class="size-4" />
                  </span>
                </div>
              </.link>
            </div>
          <% end %>
        </section>
      </div>

      <.dialog
        id="organization-dialog"
        show={@show_create_modal?}
        size="md"
        title="Create organization"
        class="bg-black/55 backdrop-blur-sm sm:rounded-3xl sm:border-border/80 sm:px-6 sm:py-6 sm:shadow-2xl sm:shadow-black/20"
        on_cancel={JS.push("close-create-modal")}
      >
        <div class="space-y-5 p-1">
          <p class="text-sm text-muted-foreground">
            Choose a clear name for the workspace your team will share.
          </p>

          <.form
            for={@form}
            id="organization-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-5"
          >
            <.input
              field={@form[:name]}
              type="text"
              label="Organization name"
              placeholder="Product Engineering"
            />
          </.form>
        </div>
        <:footer>
          <div class="flex justify-end gap-3 pt-2">
            <.button type="button" variant="outline" phx-click="close-create-modal">
              Cancel
            </.button>
            <.button
              id="save-organization-button"
              type="button"
              phx-click={JS.dispatch("submit", to: "#organization-form")}
              phx-disable-with="Creating..."
            >
              Create Organization
            </.button>
          </div>
        </:footer>
      </.dialog>
    </Layouts.app>
    """
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :organization))
  end

  defp switch_path(organization_id, return_to) when is_binary(return_to) do
    ~p"/organizations/switch/#{organization_id}?return_to=#{return_to}"
  end

  defp switch_path(organization_id, _return_to), do: ~p"/organizations/switch/#{organization_id}"

  defp organization_role_label("owner"), do: "Full access owner"
  defp organization_role_label("admin"), do: "Workspace admin"
  defp organization_role_label("member"), do: "Workspace member"
  defp organization_role_label(_role), do: "Workspace member"

  defp active_organization?(membership, current_scope) do
    current_scope.organization && membership.organization_id == current_scope.organization.id
  end
end
