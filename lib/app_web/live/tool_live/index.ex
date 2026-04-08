defmodule AppWeb.ToolLive.Index do
  use AppWeb, :live_view

  alias App.Tools
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    tools = Tools.list_tools(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Tools")
     |> assign(:can_manage_organization?, Scope.manager?(socket.assigns.current_scope))
     |> stream_configure(:tools, dom_id: &"tool-#{&1.id}")
     |> stream(:tools, tools)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if socket.assigns.can_manage_organization? do
      tool = Tools.get_tool!(socket.assigns.current_scope, id)
      {:ok, _tool} = Tools.delete_tool(socket.assigns.current_scope, tool)

      {:noreply, stream_delete(socket, :tools, tool)}
    else
      {:noreply,
       put_flash(socket, :error, "Only organization owners and admins can manage tools.")}
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
        <div class="space-y-6">
          <div class="border-b border-border pb-6">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div class="space-y-2">
                <h1 class="text-3xl font-bold tracking-tight text-foreground">Tools</h1>
                <p class="text-sm text-muted-foreground">
                  Manage reusable HTTP tools, including URL templates with runtime placeholders like <code phx-no-curly-interpolation>/{dynamic_path}</code>.
                </p>
              </div>

              <.link :if={@can_manage_organization?} id="new-tool-button" navigate={~p"/tools/create"}>
                <.button>Create Tool</.button>
              </.link>
            </div>
          </div>

          <p
            :if={not @can_manage_organization?}
            class="rounded-2xl border border-border bg-muted/30 px-4 py-3 text-sm text-muted-foreground"
          >
            Tools can only be managed by organization owners and admins.
          </p>

          <div id="tools" phx-update="stream" class="rounded-lg border border-border bg-card">
            <div
              :for={{dom_id, tool} <- @streams.tools}
              id={dom_id}
              class="flex items-center justify-between gap-4 border-b border-border p-4 last:border-b-0"
            >
              <p class="font-medium text-foreground">{tool.name}</p>

              <div :if={@can_manage_organization?} class="flex gap-2">
                <.link id={"edit-tool-#{tool.id}"} navigate={~p"/tools/#{tool.id}/edit"}>
                  <.button variant="outline">Edit</.button>
                </.link>
                <.button
                  id={"delete-tool-#{tool.id}"}
                  phx-click="delete"
                  phx-value-id={tool.id}
                  data-confirm="Are you sure?"
                  variant="outline"
                >
                  Delete
                </.button>
              </div>
            </div>

            <div
              id="tools-empty-state"
              class="hidden p-10 text-center text-sm text-muted-foreground only:block"
            >
              No tools created yet.
            </div>
          </div>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end
end
