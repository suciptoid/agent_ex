defmodule AppWeb.ToolLive.Create do
  use AppWeb, :live_view

  alias App.Tools
  alias App.Tools.Tool

  @impl true
  def mount(_params, _session, socket) do
    changeset = Tools.change_tool(%Tool{})

    {:ok,
     socket
     |> assign(:page_title, "Create Tool")
     |> assign(:saved_tools, Tools.list_tools(socket.assigns.current_scope))
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"tool" => tool_params}, socket) do
    changeset =
      %Tool{}
      |> Tools.change_tool(normalize_tool_params(tool_params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"tool" => tool_params}, socket) do
    case Tools.create_tool(socket.assigns.current_scope, normalize_tool_params(tool_params)) do
      {:ok, _tool} ->
        changeset = Tools.change_tool(%Tool{})

        {:noreply,
         socket
         |> put_flash(:info, "Tool created successfully")
         |> assign(:saved_tools, Tools.list_tools(socket.assigns.current_scope))
         |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("add-param", _params, socket) do
    {:noreply,
     update_form_rows(socket, :param_rows, fn rows ->
       rows ++ [Tool.blank_param_row()]
     end)}
  end

  def handle_event("remove-param", %{"index" => index}, socket) do
    {:noreply,
     update_form_rows(socket, :param_rows, fn rows ->
       rows
       |> List.delete_at(String.to_integer(index))
       |> ensure_rows(:param)
     end)}
  end

  def handle_event("add-header", _params, socket) do
    {:noreply,
     update_form_rows(socket, :header_rows, fn rows ->
       rows ++ [Tool.blank_header_row()]
     end)}
  end

  def handle_event("remove-header", %{"index" => index}, socket) do
    {:noreply,
     update_form_rows(socket, :header_rows, fn rows ->
       rows
       |> List.delete_at(String.to_integer(index))
       |> ensure_rows(:header)
     end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto flex w-full max-w-6xl flex-col gap-6 xl:flex-row">
        <section class="flex-1 space-y-6">
          <div class="space-y-2 border-b border-border pb-6">
            <div class="flex items-center gap-3">
              <span class="inline-flex rounded-full border border-primary/20 bg-primary/10 px-3 py-1 text-xs font-medium uppercase tracking-[0.2em] text-primary">
                HTTP Tool Builder
              </span>
            </div>

            <h1 class="text-3xl font-bold tracking-tight text-foreground">
              Create reusable API tools
            </h1>

            <p class="max-w-3xl text-sm text-muted-foreground">
              Define an HTTP endpoint once, choose which parameters the LLM should fill at runtime,
              lock fixed values such as `safe_search=true`, and store headers like `Authorization`
              securely for future agent runs.
            </p>
          </div>

          <.form for={@form} id="tool-form" phx-change="validate" phx-submit="save" class="space-y-8">
            <div class="grid gap-4 lg:grid-cols-2">
              <.input
                field={@form[:name]}
                type="text"
                label="Tool name"
                placeholder="brave_search"
              />

              <.select
                field={@form[:http_method]}
                label="HTTP method"
                options={Enum.map(Tool.http_methods(), &{String.upcase(&1), &1})}
              />
            </div>

            <.input
              field={@form[:description]}
              type="text"
              label="Description"
              placeholder="Search the web with Brave and return JSON results."
            />

            <.input
              field={@form[:endpoint]}
              type="text"
              label="API endpoint"
              placeholder="https://api.search.brave.com/res/v1/web/search"
            />

            <section class="space-y-4 rounded-3xl border border-border bg-card/70 p-5 shadow-sm">
              <div class="flex items-center justify-between gap-4">
                <div>
                  <h2 class="text-lg font-semibold text-foreground">Input parameters</h2>
                  <p class="text-sm text-muted-foreground">
                    Choose which params are filled by the LLM at runtime and which ones stay fixed.
                  </p>
                </div>

                <.button id="add-param-button" type="button" variant="outline" phx-click="add-param">
                  Add parameter
                </.button>
              </div>

              <%= for {row, index} <- Enum.with_index(param_rows(@form)) do %>
                <div
                  id={"param-row-#{index}"}
                  class="grid gap-3 rounded-2xl border border-border/70 bg-background p-4 md:grid-cols-[minmax(0,1.2fr)_160px_160px_minmax(0,1fr)_auto]"
                >
                  <div class="space-y-2">
                    <label
                      class="text-sm font-medium text-foreground"
                      for={"tool-param-#{index}-name"}
                    >
                      Name
                    </label>
                    <input
                      id={"tool-param-#{index}-name"}
                      name={"tool[param_rows][#{index}][name]"}
                      value={row["name"]}
                      type="text"
                      class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      placeholder="query"
                    />
                  </div>

                  <div class="space-y-2">
                    <label
                      class="text-sm font-medium text-foreground"
                      for={"tool-param-#{index}-type"}
                    >
                      Type
                    </label>
                    <select
                      id={"tool-param-#{index}-type"}
                      name={"tool[param_rows][#{index}][type]"}
                      class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <option
                        :for={type <- Tool.param_types()}
                        value={type}
                        selected={row["type"] == type}
                      >
                        {type}
                      </option>
                    </select>
                  </div>

                  <div class="space-y-2">
                    <label
                      class="text-sm font-medium text-foreground"
                      for={"tool-param-#{index}-source"}
                    >
                      Filled by
                    </label>
                    <select
                      id={"tool-param-#{index}-source"}
                      name={"tool[param_rows][#{index}][source]"}
                      class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <option
                        :for={source <- Tool.tool_sources()}
                        value={source}
                        selected={row["source"] == source}
                      >
                        {source_label(source)}
                      </option>
                    </select>
                  </div>

                  <div class="space-y-2">
                    <label
                      class="text-sm font-medium text-foreground"
                      for={"tool-param-#{index}-value"}
                    >
                      Fixed value
                    </label>
                    <input
                      id={"tool-param-#{index}-value"}
                      name={"tool[param_rows][#{index}][value]"}
                      value={row["value"]}
                      type="text"
                      class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      placeholder="true"
                    />
                  </div>

                  <div class="flex items-end justify-end">
                    <.button
                      id={"remove-param-#{index}"}
                      type="button"
                      variant="outline"
                      phx-click="remove-param"
                      phx-value-index={index}
                    >
                      Remove
                    </.button>
                  </div>
                </div>
              <% end %>

              <%= for {message, _opts} <- Keyword.get_values(@form.errors, :param_rows) do %>
                <p class="text-sm text-destructive">{message}</p>
              <% end %>
            </section>

            <section class="space-y-4 rounded-3xl border border-border bg-card/70 p-5 shadow-sm">
              <div class="flex items-center justify-between gap-4">
                <div>
                  <h2 class="text-lg font-semibold text-foreground">Headers</h2>
                  <p class="text-sm text-muted-foreground">
                    Store secret headers such as API keys or bearer tokens securely at creation time.
                  </p>
                </div>

                <.button id="add-header-button" type="button" variant="outline" phx-click="add-header">
                  Add header
                </.button>
              </div>

              <%= for {row, index} <- Enum.with_index(header_rows(@form)) do %>
                <div
                  id={"header-row-#{index}"}
                  class="grid gap-3 rounded-2xl border border-border/70 bg-background p-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_auto]"
                >
                  <div class="space-y-2">
                    <label
                      class="text-sm font-medium text-foreground"
                      for={"tool-header-#{index}-key"}
                    >
                      Header name
                    </label>
                    <input
                      id={"tool-header-#{index}-key"}
                      name={"tool[header_rows][#{index}][key]"}
                      value={row["key"]}
                      type="text"
                      class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      placeholder="Authorization"
                    />
                  </div>

                  <div class="space-y-2">
                    <label
                      class="text-sm font-medium text-foreground"
                      for={"tool-header-#{index}-value"}
                    >
                      Header value
                    </label>
                    <input
                      id={"tool-header-#{index}-value"}
                      name={"tool[header_rows][#{index}][value]"}
                      value={row["value"]}
                      type="password"
                      class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      placeholder="Bearer ..."
                    />
                  </div>

                  <div class="flex items-end justify-end">
                    <.button
                      id={"remove-header-#{index}"}
                      type="button"
                      variant="outline"
                      phx-click="remove-header"
                      phx-value-index={index}
                    >
                      Remove
                    </.button>
                  </div>
                </div>
              <% end %>

              <%= for {message, _opts} <- Keyword.get_values(@form.errors, :header_rows) do %>
                <p class="text-sm text-destructive">{message}</p>
              <% end %>
            </section>

            <div class="flex justify-end">
              <.button id="save-tool-button" type="submit" phx-disable-with="Saving...">
                Save tool
              </.button>
            </div>
          </.form>
        </section>

        <aside class="w-full shrink-0 space-y-4 xl:w-[22rem]">
          <section class="rounded-3xl border border-border bg-card p-5 shadow-sm">
            <div class="space-y-2">
              <h2 class="text-lg font-semibold text-foreground">Builtin tools</h2>
              <p class="text-sm text-muted-foreground">
                Every agent can also opt into `web_fetch` and the cautionary `shell` tool.
              </p>
            </div>

            <div class="mt-4 space-y-3">
              <div class="rounded-2xl border border-border bg-background p-4">
                <p class="text-sm font-medium text-foreground">web_fetch</p>
                <p class="mt-1 text-xs text-muted-foreground">
                  Fetches a URL and now accepts optional request headers for authenticated requests.
                </p>
              </div>

              <div class="rounded-2xl border border-amber-500/30 bg-amber-500/5 p-4">
                <p class="text-sm font-medium text-foreground">shell</p>
                <p class="mt-1 text-xs text-muted-foreground">
                  Runs a shell command on the host system and returns stdout/stderr. Use with caution.
                </p>
              </div>
            </div>
          </section>

          <section class="rounded-3xl border border-border bg-card p-5 shadow-sm">
            <div class="space-y-2">
              <h2 class="text-lg font-semibold text-foreground">Saved tools</h2>
              <p class="text-sm text-muted-foreground">
                Reusable HTTP tools available to the current user.
              </p>
            </div>

            <div class="mt-4 space-y-3">
              <%= for tool <- @saved_tools do %>
                <div
                  id={"saved-tool-#{tool.id}"}
                  class="rounded-2xl border border-border bg-background p-4"
                >
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <p class="text-sm font-semibold text-foreground">{tool.name}</p>
                      <p class="mt-1 text-xs uppercase tracking-wide text-primary">
                        {String.upcase(tool.http_method)}
                      </p>
                    </div>

                    <span class="rounded-full bg-muted px-2.5 py-1 text-[11px] font-medium text-muted-foreground">
                      {length(Tool.runtime_param_items(tool))} runtime params
                    </span>
                  </div>

                  <p class="mt-3 text-xs text-muted-foreground">{tool.endpoint}</p>
                </div>
              <% end %>

              <div
                :if={@saved_tools == []}
                id="saved-tools-empty-state"
                class="rounded-2xl border border-dashed border-border bg-muted/30 p-5 text-sm text-muted-foreground"
              >
                No custom tools yet. Create one from an API endpoint to make it selectable on agents.
              </div>
            </div>
          </section>
        </aside>
      </div>
    </Layouts.dashboard>
    """
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp normalize_tool_params(tool_params) do
    tool_params
    |> Map.put("param_rows", normalize_rows(Map.get(tool_params, "param_rows", [])))
    |> Map.put("header_rows", normalize_rows(Map.get(tool_params, "header_rows", [])))
  end

  defp normalize_rows(rows) when is_map(rows) do
    rows
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {_key, value} -> value end)
  end

  defp normalize_rows(rows) when is_list(rows), do: rows
  defp normalize_rows(_rows), do: []

  defp update_form_rows(socket, field, updater) do
    params =
      (socket.assigns.form.params || %{})
      |> Map.new()
      |> Map.put_new("param_rows", param_rows(socket.assigns.form))
      |> Map.put_new("header_rows", header_rows(socket.assigns.form))
      |> Map.update!(Atom.to_string(field), updater)

    changeset = Tools.change_tool(%Tool{}, params)
    assign_form(socket, changeset)
  end

  defp ensure_rows([], :param), do: [Tool.blank_param_row()]
  defp ensure_rows([], :header), do: [Tool.blank_header_row()]
  defp ensure_rows(rows, _kind), do: rows

  defp param_rows(form),
    do: form.params["param_rows"] || form.data.param_rows || [Tool.blank_param_row()]

  defp header_rows(form),
    do: form.params["header_rows"] || form.data.header_rows || [Tool.blank_header_row()]

  defp source_label("llm"), do: "LLM at runtime"
  defp source_label("fixed"), do: "Fixed during creation"
end
