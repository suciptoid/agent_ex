defmodule AppWeb.ToolLive.Create do
  use AppWeb, :live_view

  alias App.Tools
  alias App.Tools.Tool

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("validate", %{"tool" => tool_params}, socket) do
    changeset =
      socket.assigns.tool
      |> Tools.change_tool(normalize_tool_params(tool_params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"tool" => tool_params}, socket) do
    save_tool(socket, socket.assigns.live_action, normalize_tool_params(tool_params))
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
      <div class="flex h-full min-h-0 flex-col p-4 pt-20 sm:px-5 sm:pb-5 sm:pt-20 lg:p-6">
        <div class="mx-auto flex w-full max-w-6xl flex-col gap-6 xl:flex-row">
          <section class="flex-1 space-y-6">
            <div class="space-y-3 border-b border-border pb-6">
              <div class="flex items-center justify-between gap-4">
                <span class="inline-flex rounded-full border border-primary/20 bg-primary/10 px-3 py-1 text-xs font-medium uppercase tracking-[0.2em] text-primary">
                  HTTP Tool Builder
                </span>

                <.link
                  navigate={~p"/tools/list"}
                  class="text-sm font-medium text-primary hover:underline"
                >
                  Back to tool list
                </.link>
              </div>

              <h1 class="text-3xl font-bold tracking-tight text-foreground">{@page_title}</h1>

              <p class="max-w-3xl text-sm text-muted-foreground">
                Use a URL template when the path itself needs runtime data, like <code phx-no-curly-interpolation>https://r.jina.ai/{dynamic_path}?param_a=value</code>.
                Every <code phx-no-curly-interpolation>{placeholder}</code>
                must match a parameter name below.
              </p>
            </div>

            <.form
              for={@form}
              id="tool-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-8"
            >
              <div class="grid gap-4 lg:grid-cols-2">
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Tool name"
                  placeholder="brave_reader"
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
                placeholder="Read a document through Jina's mirror."
              />

              <.input
                field={@form[:endpoint]}
                type="text"
                label="URL template"
                placeholder="https://r.jina.ai/{dynamic_path}?param_a=value"
              />

              <section class="space-y-4 rounded-3xl border border-border bg-card/70 p-5 shadow-sm">
                <div class="flex items-center justify-between gap-4">
                  <div>
                    <h2 class="text-lg font-semibold text-foreground">Input parameters</h2>
                    <p class="text-sm text-muted-foreground">
                      Parameters can feed query/body values and placeholders inside the URL template.
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
                        placeholder="dynamic_path"
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
                        placeholder="https://example.com/doc"
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
                      Store static request headers securely, such as `Authorization`.
                    </p>
                  </div>

                  <.button
                    id="add-header-button"
                    type="button"
                    variant="outline"
                    phx-click="add-header"
                  >
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

              <div class="flex justify-end gap-3">
                <.link navigate={~p"/tools/list"}>
                  <.button type="button" variant="outline">Cancel</.button>
                </.link>
                <.button id="save-tool-button" type="submit" phx-disable-with="Saving...">
                  {save_label(@live_action)}
                </.button>
              </div>
            </.form>
          </section>

          <aside class="w-full shrink-0 space-y-4 xl:w-[22rem]">
            <section class="rounded-3xl border border-border bg-card p-5 shadow-sm">
              <div class="space-y-2">
                <h2 class="text-lg font-semibold text-foreground">Template example</h2>
                <p class="text-sm text-muted-foreground">
                  Dynamic path segments should be modeled with placeholders in the URL itself.
                </p>
              </div>

              <div class="mt-4 rounded-2xl border border-border bg-background p-4 text-xs text-muted-foreground">
                <code phx-no-curly-interpolation class="block">
                  https://r.jina.ai/{dynamic_path}?param_a=value
                </code>

                <ul class="mt-3 space-y-2">
                  <li><code>dynamic_path</code> → source: LLM at runtime</li>
                  <li>
                    <code>param_a</code> → source: Fixed during creation, value: <code>value</code>
                  </li>
                </ul>
              </div>
            </section>
          </aside>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end

  defp apply_action(socket, :new, _params) do
    changeset = Tools.change_tool(%Tool{})

    socket
    |> assign(:page_title, "Create Tool")
    |> assign(:tool, %Tool{})
    |> assign_form(changeset)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    tool = Tools.get_tool!(socket.assigns.current_scope, id)
    changeset = Tools.change_tool(tool)

    socket
    |> assign(:page_title, "Edit Tool")
    |> assign(:tool, tool)
    |> assign_form(changeset)
  end

  defp save_tool(socket, :new, tool_params) do
    case Tools.create_tool(socket.assigns.current_scope, tool_params) do
      {:ok, _tool} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tool created successfully")
         |> push_navigate(to: ~p"/tools/list")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_tool(socket, :edit, tool_params) do
    case Tools.update_tool(socket.assigns.current_scope, socket.assigns.tool, tool_params) do
      {:ok, _tool} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tool updated successfully")
         |> push_navigate(to: ~p"/tools/list")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
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

    changeset = Tools.change_tool(socket.assigns.tool, params)
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

  defp save_label(:edit), do: "Save Changes"
  defp save_label(_action), do: "Save Tool"
end
