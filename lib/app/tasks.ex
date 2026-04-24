defmodule App.Tasks do
  @moduledoc """
  The background task scheduling context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias App.Agents.Agent
  alias App.Chat
  alias App.Chat.ChatRoom
  alias App.Gateways.Channel
  alias App.Organizations.Organization
  alias App.Repo
  alias App.Tasks.Schedule
  alias App.Tasks.Task, as: ScheduledTask
  alias App.Tasks.TaskAgent
  alias App.Tasks.TaskRunWorker
  alias App.Users.Scope

  @preloads [
    :main_agent,
    :notification_chat_room,
    task_agents: [agent: :provider],
    agents: [:provider]
  ]

  def list_tasks(%Scope{} = scope) do
    ScheduledTask
    |> where([task], task.organization_id == ^Scope.organization_id!(scope))
    |> order_by([task], asc_nulls_last: task.next_run, desc: task.updated_at)
    |> preload(^@preloads)
    |> Repo.all()
  end

  def get_task!(%Scope{} = scope, id) do
    ScheduledTask
    |> where([task], task.organization_id == ^Scope.organization_id!(scope) and task.id == ^id)
    |> preload(^@preloads)
    |> Repo.one!()
  end

  def get_task(%Scope{} = scope, id) do
    ScheduledTask
    |> where([task], task.organization_id == ^Scope.organization_id!(scope) and task.id == ^id)
    |> preload(^@preloads)
    |> Repo.one()
  end

  def create_task(%Scope{} = scope, attrs) do
    with :ok <- authorize_manager(scope) do
      organization_id = Scope.organization_id!(scope)
      attrs = Map.new(attrs)

      changeset =
        %ScheduledTask{organization_id: organization_id}
        |> ScheduledTask.changeset(attrs)
        |> validate_task_associations(organization_id)

      with %{valid?: true} <- changeset,
           {:ok, agents} <- fetch_agents_for_task(organization_id, changeset) do
        Multi.new()
        |> Multi.insert(:task, changeset)
        |> Multi.run(:task_agents, fn repo, %{task: task} ->
          insert_task_agents(repo, task, agents)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{task: task}} -> {:ok, get_task!(scope, task.id)}
          {:error, :task, changeset, _changes} -> {:error, changeset}
          {:error, :task_agents, changeset, _changes} -> {:error, changeset}
        end
      else
        %{valid?: false} -> {:error, changeset}
        {:error, _reason} = error -> error
      end
    end
  end

  def update_task(%Scope{} = scope, %ScheduledTask{} = task, attrs) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_task(scope, task) do
      attrs = Map.new(attrs)

      changeset =
        task
        |> prepare_task_for_form()
        |> ScheduledTask.changeset(attrs)
        |> validate_task_associations(task.organization_id)

      with %{valid?: true} <- changeset,
           {:ok, agents} <- fetch_agents_for_task(task.organization_id, changeset) do
        Multi.new()
        |> Multi.update(:task, changeset)
        |> Multi.delete_all(
          :delete_task_agents,
          from(task_agent in TaskAgent, where: task_agent.scheduled_task_id == ^task.id)
        )
        |> Multi.run(:task_agents, fn repo, %{task: updated_task} ->
          insert_task_agents(repo, updated_task, agents)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{task: updated_task}} -> {:ok, get_task!(scope, updated_task.id)}
          {:error, :task, changeset, _changes} -> {:error, changeset}
          {:error, :task_agents, changeset, _changes} -> {:error, changeset}
        end
      else
        %{valid?: false} -> {:error, changeset}
        {:error, _reason} = error -> error
      end
    end
  end

  def delete_task(%Scope{} = scope, %ScheduledTask{} = task) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_task(scope, task) do
      Repo.delete(task)
    end
  end

  def change_task(%Scope{} = scope, %ScheduledTask{} = task, attrs \\ %{}) do
    task
    |> prepare_task_for_form()
    |> ScheduledTask.changeset(attrs)
    |> validate_task_associations(Scope.organization_id!(scope))
  end

  def list_notification_chat_rooms(%Scope{} = scope) do
    from(chat_room in ChatRoom,
      join: channel in Channel,
      on: channel.chat_room_id == chat_room.id,
      where: chat_room.organization_id == ^Scope.organization_id!(scope),
      distinct: chat_room.id,
      order_by: [desc: chat_room.updated_at, desc: chat_room.inserted_at],
      select: map(chat_room, [:id, :title, :type, :updated_at, :inserted_at])
    )
    |> Repo.all()
  end

  def dispatch_due_tasks(now \\ DateTime.utc_now()) do
    ScheduledTask
    |> where([task], not is_nil(task.next_run) and task.next_run <= ^now)
    |> order_by([task], asc: task.next_run)
    |> Repo.all()
    |> Enum.each(&dispatch_task_run/1)

    :ok
  end

  def run_task(task_id, scheduled_for \\ nil) do
    case ScheduledTask |> Repo.get(task_id) |> Repo.preload(@preloads) do
      nil ->
        {:discard, :task_not_found}

      %ScheduledTask{} = task ->
        scheduled_for_datetime =
          parse_scheduled_for(scheduled_for) || task.last_run_at || DateTime.utc_now()

        with {:ok, task_room} <- create_task_room(task, scheduled_for_datetime),
             {:ok, _result} <- run_task_prompt(task, task_room),
             {:ok, _task} <-
               Repo.update(Ecto.Changeset.change(task, last_run_at: DateTime.utc_now())) do
          :ok
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def task_room_title(%ScheduledTask{name: name}, %DateTime{} = scheduled_for) do
    "#{name} - #{Calendar.strftime(scheduled_for, "%Y-%m-%d %H:%M UTC")}"
  end

  def schedule_label(%ScheduledTask{repeat: false, next_run: %DateTime{} = next_run}) do
    "Runs once at #{Calendar.strftime(next_run, "%Y-%m-%d %H:%M UTC")}"
  end

  def schedule_label(%ScheduledTask{
        repeat: true,
        schedule_type: :cron,
        cron_expression: expression
      }) do
    "Repeats with cron #{expression}"
  end

  def schedule_label(%ScheduledTask{
        repeat: true,
        schedule_type: :every,
        every_interval: interval,
        every_unit: unit
      }) do
    "Repeats every #{interval} #{unit}#{if interval == 1, do: "", else: "s"}"
  end

  def schedule_label(%ScheduledTask{}), do: "No schedule"

  def schedule_types, do: ScheduledTask.schedule_types()
  def every_units, do: ScheduledTask.every_units()

  def format_next_run_input(%ScheduledTask{} = task),
    do: Schedule.format_datetime_input(task.next_run)

  defp validate_task_associations(changeset, organization_id) do
    changeset
    |> validate_main_agent_ownership(organization_id)
    |> validate_notification_chat_room_ownership(organization_id)
  end

  defp validate_main_agent_ownership(changeset, organization_id) do
    case Ecto.Changeset.get_field(changeset, :main_agent_id) do
      nil ->
        changeset

      main_agent_id ->
        if Repo.exists?(
             from agent in Agent,
               where: agent.id == ^main_agent_id and agent.organization_id == ^organization_id
           ) do
          changeset
        else
          Ecto.Changeset.add_error(
            changeset,
            :main_agent_id,
            "must belong to the current organization"
          )
        end
    end
  end

  defp validate_notification_chat_room_ownership(changeset, organization_id) do
    case Ecto.Changeset.get_field(changeset, :notification_chat_room_id) do
      nil ->
        changeset

      chat_room_id ->
        if Repo.exists?(
             from chat_room in ChatRoom,
               where:
                 chat_room.id == ^chat_room_id and chat_room.organization_id == ^organization_id
           ) do
          changeset
        else
          Ecto.Changeset.add_error(
            changeset,
            :notification_chat_room_id,
            "must belong to the current organization"
          )
        end
    end
  end

  defp fetch_agents_for_task(organization_id, changeset) do
    agent_ids = Ecto.Changeset.get_field(changeset, :agent_ids, [])

    agents =
      from(agent in Agent,
        where: agent.organization_id == ^organization_id and agent.id in ^agent_ids
      )
      |> Repo.all()
      |> Enum.sort_by(fn agent -> Enum.find_index(agent_ids, &(&1 == agent.id)) end)

    if length(agents) == length(agent_ids) do
      {:ok, agents}
    else
      {:error,
       Ecto.Changeset.add_error(changeset, :agent_ids, "must belong to the current organization")}
    end
  end

  defp insert_task_agents(repo, task, agents) do
    Enum.reduce_while(agents, {:ok, []}, fn agent, {:ok, task_agents} ->
      params = %{scheduled_task_id: task.id, agent_id: agent.id}

      case %TaskAgent{} |> TaskAgent.changeset(params) |> repo.insert() do
        {:ok, task_agent} ->
          {:cont, {:ok, [task_agent | task_agents]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, task_agents} -> {:ok, Enum.reverse(task_agents)}
      {:error, _reason} = error -> error
    end
  end

  defp prepare_task_for_form(%ScheduledTask{} = task) do
    task =
      if Ecto.assoc_loaded?(task.task_agents) do
        %{task | agent_ids: Enum.map(task.task_agents, & &1.agent_id)}
      else
        task
      end

    %{task | next_run_input: Schedule.format_datetime_input(task.next_run)}
  end

  defp dispatch_task_run(%ScheduledTask{} = task) do
    Repo.transaction(fn ->
      locked_task =
        ScheduledTask
        |> where([scheduled_task], scheduled_task.id == ^task.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if is_nil(locked_task.next_run) do
        :ok
      else
        next_run =
          case Schedule.next_run_after(locked_task, locked_task.next_run) do
            {:ok, next_run} -> next_run
            _other -> nil
          end

        locked_task
        |> Ecto.Changeset.change(next_run: next_run)
        |> Repo.update!()

        %{
          task_id: locked_task.id,
          scheduled_for: DateTime.to_iso8601(locked_task.next_run)
        }
        |> TaskRunWorker.new(queue: :scheduled_tasks)
        |> Oban.insert!()
      end
    end)
  end

  defp create_task_room(%ScheduledTask{} = task, %DateTime{} = scheduled_for) do
    scope = %Scope{
      user: nil,
      organization: %Organization{id: task.organization_id},
      organization_role: "admin"
    }

    Chat.create_chat_room(scope, %{
      title: task_room_title(task, scheduled_for),
      type: :task,
      agent_ids: Enum.map(task.task_agents, & &1.agent_id),
      active_agent_id: task.main_agent_id
    })
  end

  defp run_task_prompt(%ScheduledTask{} = task, %ChatRoom{} = chat_room) do
    extra_tools =
      if is_nil(task.notification_chat_room_id) do
        []
      else
        [App.Agents.AlloyTools.ChannelSendMessage]
      end

    Chat.send_system_message(chat_room, task.prompt,
      name: task.name,
      extra_tools: extra_tools,
      alloy_context: %{
        task_id: task.id,
        task_name: task.name,
        task_chat_room_id: chat_room.id,
        notification_chat_room_id: task.notification_chat_room_id,
        notification_chat_room: task.notification_chat_room
      }
    )
  end

  defp parse_scheduled_for(nil), do: nil

  defp parse_scheduled_for(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> %{datetime | microsecond: {0, 6}}
      _other -> nil
    end
  end

  defp authorize_manager(%Scope{} = scope) do
    if Scope.manager?(scope), do: :ok, else: {:error, :forbidden}
  end

  defp ensure_organization_owns_task(%Scope{} = scope, %ScheduledTask{
         organization_id: organization_id
       }) do
    if organization_id == Scope.organization_id!(scope) do
      :ok
    else
      raise Ecto.NoResultsError, query: ScheduledTask
    end
  end
end
