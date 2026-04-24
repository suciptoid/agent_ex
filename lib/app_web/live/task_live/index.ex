defmodule AppWeb.TaskLive.Index do
  use AppWeb, :live_view

  alias App.Tasks
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    if Scope.manager?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(:page_title, "Tasks")
       |> assign(:tasks, Tasks.list_tasks(socket.assigns.current_scope))}
    else
      {:ok,
       socket
       |> assign(:page_title, "Tasks")
       |> assign(:tasks, [])
       |> put_flash(:error, "Only organization owners and admins can manage scheduled tasks.")
       |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("delete-task", %{"id" => id}, socket) do
    socket =
      case Tasks.get_task(socket.assigns.current_scope, id) do
        nil ->
          socket
          |> refresh_tasks()
          |> put_flash(:error, "Task not found.")

        task ->
          case Tasks.delete_task(socket.assigns.current_scope, task) do
            {:ok, _task} ->
              socket
              |> refresh_tasks()
              |> put_flash(:info, "Task deleted.")

            {:error, _reason} ->
              socket
              |> refresh_tasks()
              |> put_flash(:error, "Failed to delete task.")
          end
      end

    {:noreply, socket}
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
      <div class="flex h-full min-h-0 flex-col gap-6 p-4 sm:p-6 lg:p-8">
        <section class="rounded-3xl border border-border/70 bg-card px-5 py-5 shadow-sm sm:px-6 sm:py-6 lg:px-8">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div class="space-y-2">
              <p class="text-[11px] font-semibold uppercase tracking-[0.22em] text-muted-foreground">
                Background automation
              </p>
              <div class="space-y-1">
                <h1 id="tasks-heading" class="text-2xl font-semibold tracking-tight text-foreground">
                  Scheduled tasks
                </h1>
                <p class="max-w-3xl text-sm leading-6 text-muted-foreground">
                  Schedule repeatable prompts, assign multiple agents, and save each run as a task chat room.
                </p>
              </div>
            </div>

            <.link navigate={~p"/tasks/new"}>
              <.button id="new-task-button" class="gap-2 shadow-none">
                <.icon name="hero-plus" class="size-4" /> New task
              </.button>
            </.link>
          </div>
        </section>

        <section class="min-h-0 flex-1 overflow-hidden rounded-3xl border border-border/70 bg-card shadow-sm">
          <div class="flex h-full min-h-0 flex-col">
            <div class="border-b border-border/70 px-5 py-4 sm:px-6">
              <p class="text-sm text-muted-foreground">
                <span class="font-semibold text-foreground">{length(@tasks)}</span>
                scheduled tasks configured for this organization.
              </p>
            </div>

            <div class="min-h-0 flex-1 overflow-y-auto">
              <div :if={@tasks == []} id="tasks-empty-state" class="px-5 py-12 text-center sm:px-6">
                <div class="mx-auto flex max-w-md flex-col items-center gap-3">
                  <div class="flex size-14 items-center justify-center rounded-2xl bg-muted text-muted-foreground">
                    <.icon name="hero-clock" class="size-7" />
                  </div>
                  <div class="space-y-1">
                    <p class="text-base font-semibold text-foreground">No scheduled tasks yet</p>
                    <p class="text-sm text-muted-foreground">
                      Create one to run prompts automatically and keep the transcript in task chat rooms.
                    </p>
                  </div>
                </div>
              </div>

              <div :if={@tasks != []} id="tasks-list" class="divide-y divide-border/70">
                <div
                  :for={task <- @tasks}
                  id={"task-row-#{task.id}"}
                  class="flex flex-col gap-4 px-5 py-4 sm:px-6 lg:flex-row lg:items-center lg:justify-between"
                >
                  <div class="min-w-0 flex-1 space-y-2">
                    <div class="flex flex-wrap items-center gap-2">
                      <.link
                        id={"task-edit-link-#{task.id}"}
                        navigate={~p"/tasks/#{task.id}/edit"}
                        class="truncate text-sm font-semibold text-foreground transition-colors hover:text-primary"
                      >
                        {task.name}
                      </.link>

                      <span class="inline-flex items-center rounded-full border border-primary/15 bg-primary/5 px-2 py-0.5 text-[11px] font-medium text-primary">
                        {Tasks.schedule_label(task)}
                      </span>

                      <span
                        :if={task.notification_chat_room}
                        id={"task-channel-badge-#{task.id}"}
                        class="inline-flex items-center gap-1 rounded-full border border-border bg-muted px-2 py-0.5 text-[11px] font-medium text-muted-foreground"
                      >
                        <.icon name="hero-signal" class="size-3" />
                        {task.notification_chat_room.title || "Linked channel"}
                      </span>
                    </div>

                    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
                      <span>{length(task.task_agents)} agents</span>
                      <span>Main agent: {task.main_agent && task.main_agent.name}</span>
                      <span :if={task.last_run_at}>
                        Last run {Calendar.strftime(task.last_run_at, "%Y-%m-%d %H:%M UTC")}
                      </span>
                      <span :if={task.next_run}>
                        Next run {Calendar.strftime(task.next_run, "%Y-%m-%d %H:%M UTC")}
                      </span>
                    </div>
                  </div>

                  <div class="flex flex-wrap items-center gap-2 lg:justify-end">
                    <.link navigate={~p"/tasks/#{task.id}/edit"}>
                      <.button id={"task-edit-button-#{task.id}"} variant="outline" class="gap-2">
                        <.icon name="hero-pencil-square" class="size-4" /> Edit
                      </.button>
                    </.link>

                    <.button
                      id={"task-delete-button-#{task.id}"}
                      type="button"
                      variant="destructive"
                      phx-click="delete-task"
                      phx-value-id={task.id}
                      data-confirm="Delete this task?"
                      class="gap-2"
                    >
                      <.icon name="hero-trash" class="size-4" /> Delete
                    </.button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.dashboard>
    """
  end

  defp refresh_tasks(socket) do
    assign(socket, :tasks, Tasks.list_tasks(socket.assigns.current_scope))
  end
end
