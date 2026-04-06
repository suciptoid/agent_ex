defmodule AppWeb.ToolLive.Index do
  use AppWeb, :live_view

  alias App.Tools
  alias App.Tools.Tool

  @impl true
  def mount(_params, _session, socket) do
    tools = Tools.list_tools(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Tools")
     |> stream_configure(:tools, dom_id: &"tool-#{&1.id}")
     |> stream(:tools, tools)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      sidebar_chat_rooms={@sidebar_chat_rooms}
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

              <.link id="new-tool-button" navigate={~p"/tools/create"}>
                <.button>Create Tool</.button>
              </.link>
            </div>
          </div>

          <div id="tools" phx-update="stream" class="grid gap-4 xl:grid-cols-2">
            <div
              :for={{dom_id, tool} <- @streams.tools}
              id={dom_id}
              class="rounded-2xl border border-border bg-card p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="space-y-2">
                  <div class="flex flex-wrap items-center gap-2">
                    <h2 class="text-lg font-semibold text-foreground">{tool.name}</h2>
                    <span class="inline-flex items-center rounded-full bg-primary/10 px-2.5 py-1 text-xs font-medium text-primary">
                      {String.upcase(tool.http_method)}
                    </span>
                  </div>
                  <p class="text-sm text-muted-foreground">{tool.description}</p>
                </div>

                <.link id={"edit-tool-#{tool.id}"} navigate={~p"/tools/#{tool.id}/edit"}>
                  <.button variant="outline">Edit</.button>
                </.link>
              </div>

              <div class="mt-4 rounded-2xl border border-border bg-background p-4">
                <p class="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  URL Template
                </p>
                <p class="mt-2 break-all text-sm text-foreground">{tool.endpoint}</p>
              </div>

              <div class="mt-4 flex flex-wrap gap-2">
                <span class="inline-flex items-center rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                  {length(Tool.runtime_param_items(tool))} runtime params
                </span>
                <span class="inline-flex items-center rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                  {length(Tool.static_param_items(tool))} fixed params
                </span>
                <span class="inline-flex items-center rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground">
                  {length(Tool.template_placeholders(tool))} path placeholders
                </span>
              </div>
            </div>

            <div
              id="tools-empty-state"
              class="hidden rounded-2xl border border-dashed border-border bg-muted/30 p-10 text-center text-sm text-muted-foreground only:block"
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
