defmodule AppWeb.TaskLive.Form do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Tasks
  alias App.Tasks.Task, as: ScheduledTask
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    if Scope.manager?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(:available_agents, Agents.list_agents(socket.assigns.current_scope))
       |> assign(
         :notification_chat_rooms,
         Tasks.list_notification_chat_rooms(socket.assigns.current_scope)
       )}
    else
      {:ok,
       socket
       |> assign(:available_agents, [])
       |> assign(:notification_chat_rooms, [])
       |> assign(:task, %ScheduledTask{})
       |> assign(
         :form,
         to_form(Tasks.change_task(socket.assigns.current_scope, %ScheduledTask{}))
       )
       |> put_flash(:error, "Only organization owners and admins can manage scheduled tasks.")
       |> push_navigate(to: ~p"/tasks")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("validate", %{"task" => task_params}, socket) do
    changeset =
      Tasks.change_task(socket.assigns.current_scope, socket.assigns.task, task_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"task" => task_params}, socket) do
    save_task(socket, socket.assigns.live_action, task_params)
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
        <div id={task_page_id(@live_action)} class="mx-auto w-full max-w-5xl">
          <section class="space-y-6">
            <div class="space-y-3 border-b border-border pb-6">
              <.link
                navigate={~p"/tasks"}
                class="inline-flex w-fit items-center gap-2 text-sm text-muted-foreground transition hover:text-foreground"
              >
                <.icon name="hero-arrow-left" class="size-4" />
                <span>Back to tasks</span>
              </.link>

              <div class="space-y-2">
                <h1 class="text-3xl font-bold tracking-tight text-foreground">{@page_title}</h1>
                <p class="text-sm text-muted-foreground">
                  Configure when the task runs, which agents participate, and where notifications should be delivered.
                </p>
              </div>
            </div>

            <.form
              for={@form}
              id="task-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-8"
            >
              <div class="grid gap-4 lg:grid-cols-2">
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Task name"
                  placeholder="Daily standup summary"
                />
                <div class="space-y-2">
                  <label class="text-sm font-medium text-foreground" for="task-next-run-input">
                    Run at (UTC)
                  </label>
                  <input
                    id="task-next-run-input"
                    name="task[next_run_input]"
                    type="datetime-local"
                    value={@form[:next_run_input].value}
                    class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  />
                  <%= if @form.source.action do %>
                    <%= for {message, _opts} <- Keyword.get_values(@form.errors, :next_run_input) do %>
                      <p class="text-sm text-destructive">{message}</p>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <.input
                field={@form[:prompt]}
                type="textarea"
                label="Prompt / instruction"
                placeholder="Summarize yesterday's commits and notify the team channel with the key blockers."
              />

              <section class="space-y-4 rounded-lg border border-border bg-card/70 p-5 shadow-sm">
                <div class="space-y-1">
                  <p class="text-sm font-medium text-foreground">Assigned agents</p>
                  <p class="text-xs leading-5 text-muted-foreground">
                    Select every agent that should be available in the task run, then choose the main active agent below.
                  </p>
                </div>

                <input type="hidden" name="task[agent_ids][]" value="" />

                <div class="grid gap-3 md:grid-cols-2">
                  <label
                    :for={agent <- @available_agents}
                    for={"task-agent-#{agent.id}"}
                    class={[
                      "flex items-start gap-3 rounded-xl border p-4 transition",
                      if(agent_selected?(@form[:agent_ids].value, agent.id),
                        do: "border-primary bg-primary/5",
                        else: "border-border hover:border-primary/40"
                      )
                    ]}
                  >
                    <.checkbox
                      id={"task-agent-#{agent.id}"}
                      name="task[agent_ids][]"
                      value={agent.id}
                      checked={agent_selected?(@form[:agent_ids].value, agent.id)}
                    />
                    <div class="space-y-1">
                      <p class="text-sm font-medium text-foreground">{agent.name}</p>
                      <p class="text-xs text-muted-foreground">
                        {agent.provider &&
                          "#{agent.provider.name || agent.provider.provider} / #{agent.model}"}
                      </p>
                    </div>
                  </label>
                </div>

                <%= if @form.source.action do %>
                  <%= for {message, _opts} <- Keyword.get_values(@form.errors, :agent_ids) do %>
                    <p class="text-sm text-destructive">{message}</p>
                  <% end %>
                <% end %>

                <.native_select
                  field={@form[:main_agent_id]}
                  label="Main active agent"
                  options={
                    main_agent_options(
                      @available_agents,
                      @form[:agent_ids].value,
                      @form[:main_agent_id].value
                    )
                  }
                  prompt="Select the agent that should lead the task"
                />
              </section>

              <section class="space-y-4 rounded-lg border border-border bg-card/70 p-5 shadow-sm">
                <div class="space-y-2">
                  <input type="hidden" name={@form[:repeat].name} value="false" />

                  <.checkbox
                    id={@form[:repeat].id}
                    name={@form[:repeat].name}
                    value="true"
                    checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:repeat].value)}
                    label="Repeat automatically"
                  />
                </div>

                <%= if Phoenix.HTML.Form.normalize_value("checkbox", @form[:repeat].value) do %>
                  <div class="grid gap-4 lg:grid-cols-[220px_minmax(0,1fr)]">
                    <.native_select
                      field={@form[:schedule_type]}
                      label="Repeat mode"
                      options={schedule_type_options()}
                      prompt="Select repeat mode"
                    />

                    <%= case @form[:schedule_type].value do %>
                      <% :cron -> %>
                        <.input
                          field={@form[:cron_expression]}
                          type="text"
                          label="Cron expression"
                          placeholder="0 9 * * 1-5"
                        />
                      <% _ -> %>
                        <div class="grid gap-4 sm:grid-cols-[160px_minmax(0,1fr)]">
                          <.input
                            field={@form[:every_interval]}
                            type="number"
                            min="1"
                            label="Every"
                            placeholder="1"
                          />
                          <.native_select
                            field={@form[:every_unit]}
                            label="Unit"
                            options={every_unit_options()}
                            prompt="Select interval unit"
                          />
                        </div>
                    <% end %>
                  </div>
                <% end %>
              </section>

              <section class="space-y-4 rounded-lg border border-border bg-card/70 p-5 shadow-sm">
                <div class="space-y-1">
                  <p class="text-sm font-medium text-foreground">Notifications</p>
                  <p class="text-xs leading-5 text-muted-foreground">
                    Optional. When selected, task runs can use the `channel_send_message` tool to write into that active gateway chat room and relay externally.
                  </p>
                </div>

                <.native_select
                  field={@form[:notification_chat_room_id]}
                  label="Notification chat room"
                  options={notification_chat_room_options(@notification_chat_rooms)}
                  prompt="No linked channel"
                />
              </section>

              <div class="flex flex-wrap items-center justify-end gap-3 border-t border-border pt-6">
                <.link navigate={~p"/tasks"}>
                  <.button type="button" variant="outline">Cancel</.button>
                </.link>
                <.button id="save-task-button" type="submit">{save_label(@live_action)}</.button>
              </div>
            </.form>
          </section>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end

  defp apply_action(socket, :new, _params) do
    task = %ScheduledTask{}

    socket
    |> assign(:page_title, "Create Task")
    |> assign(:task, task)
    |> assign(:form, to_form(Tasks.change_task(socket.assigns.current_scope, task)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    task = Tasks.get_task!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Task")
    |> assign(:task, task)
    |> assign(:form, to_form(Tasks.change_task(socket.assigns.current_scope, task)))
  end

  defp save_task(socket, :new, task_params) do
    case Tasks.create_task(socket.assigns.current_scope, task_params) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "Task created.")
         |> push_navigate(to: ~p"/tasks")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  defp save_task(socket, :edit, task_params) do
    case Tasks.update_task(socket.assigns.current_scope, socket.assigns.task, task_params) do
      {:ok, task} ->
        {:noreply,
         socket
         |> assign(:task, task)
         |> put_flash(:info, "Task updated.")
         |> push_navigate(to: ~p"/tasks")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :update)))}
    end
  end

  defp save_label(:edit), do: "Save Changes"
  defp save_label(_action), do: "Create Task"

  defp task_page_id(:edit), do: "task-edit-page"
  defp task_page_id(_action), do: "task-create-page"

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :options, :list, default: []
  attr :prompt, :string, default: nil

  defp native_select(assigns) do
    assigns = assign(assigns, :errors, field_errors(assigns.field))

    ~H"""
    <div class="space-y-2">
      <label class="text-sm font-medium text-foreground" for={@field.id}>
        {@label}
      </label>
      <select
        id={@field.id}
        name={@field.name}
        class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm shadow-sm transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-60"
      >
        <option :if={@prompt} value="" selected={blank_select_value?(@field.value)}>
          {@prompt}
        </option>
        <option
          :for={{value, label} <- @options}
          value={value}
          selected={select_value?(@field.value, value)}
        >
          {label}
        </option>
      </select>
      <p :for={error <- @errors} class="text-sm text-destructive">{error}</p>
    </div>
    """
  end

  defp normalize_ids(nil), do: []
  defp normalize_ids(ids) when is_list(ids), do: Enum.reject(ids, &(&1 in [nil, ""]))
  defp normalize_ids(id) when is_binary(id), do: [id]
  defp normalize_ids(_ids), do: []

  defp agent_selected?(value, agent_id), do: agent_id in normalize_ids(value)

  defp main_agent_options(agents, selected_agent_ids, current_main_agent_id) do
    selected_ids =
      selected_agent_ids
      |> normalize_ids()
      |> Kernel.++(normalize_ids(current_main_agent_id))
      |> Enum.uniq()

    agents
    |> Enum.filter(&(&1.id in selected_ids))
    |> Enum.map(&{&1.id, &1.name})
  end

  defp notification_chat_room_options(chat_rooms) do
    Enum.map(chat_rooms, fn chat_room ->
      label = "#{chat_room.title || "Untitled"} (#{String.capitalize(to_string(chat_room.type))})"
      {chat_room.id, label}
    end)
  end

  defp schedule_type_options do
    Enum.map(Tasks.schedule_types(), fn
      :cron -> {"cron", "Cron expression"}
      :every -> {"every", "Every interval"}
      type -> {to_string(type), String.capitalize(to_string(type))}
    end)
  end

  defp every_unit_options do
    Enum.map(Tasks.every_units(), fn unit ->
      {to_string(unit), String.capitalize(to_string(unit))}
    end)
  end

  defp field_errors(field) do
    if Phoenix.Component.used_input?(field) do
      Enum.map(field.errors, &translate_error/1)
    else
      []
    end
  end

  defp blank_select_value?(value), do: value in [nil, ""]

  defp select_value?(current_value, option_value),
    do: to_string(current_value) == to_string(option_value)
end
