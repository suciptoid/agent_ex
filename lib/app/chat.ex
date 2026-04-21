defmodule App.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias App.Agents.Agent
  alias App.Chat.{ChatRoom, ChatRoomAgent, Message}
  alias App.Organizations.Membership
  alias App.Repo
  alias App.Users.Scope
  alias App.Users.User

  def list_chat_rooms(%Scope{} = scope) do
    ChatRoom
    |> where([chat_room], chat_room.organization_id == ^Scope.organization_id!(scope))
    |> order_by([chat_room], desc: chat_room.updated_at, desc: chat_room.inserted_at)
    |> preload(^chat_room_preloads())
    |> Repo.all()
  end

  def count_chat_rooms(%Scope{} = scope) do
    Repo.aggregate(
      from(chat_room in ChatRoom,
        where: chat_room.organization_id == ^Scope.organization_id!(scope)
      ),
      :count,
      :id
    )
  end

  def list_recent_chat_rooms(%Scope{} = scope, limit \\ 5) when is_integer(limit) and limit > 0 do
    ChatRoom
    |> where([chat_room], chat_room.organization_id == ^Scope.organization_id!(scope))
    |> order_by([chat_room], desc: chat_room.updated_at, desc: chat_room.inserted_at)
    |> limit(^limit)
    |> preload([:agents])
    |> Repo.all()
  end

  def get_chat_room!(%Scope{} = scope, id) do
    ChatRoom
    |> where(
      [chat_room],
      chat_room.organization_id == ^Scope.organization_id!(scope) and chat_room.id == ^id
    )
    |> preload(^chat_room_preloads())
    |> Repo.one!()
  end

  def get_chat_room(%Scope{} = scope, id) do
    ChatRoom
    |> where(
      [chat_room],
      chat_room.organization_id == ^Scope.organization_id!(scope) and chat_room.id == ^id
    )
    |> preload(^chat_room_preloads())
    |> Repo.one()
  end

  def preload_chat_room(%ChatRoom{} = chat_room) do
    Repo.preload(chat_room, chat_room_preloads())
  end

  def get_chat_room_for_user(%User{} = user, id) do
    ChatRoom
    |> join(:inner, [chat_room], membership in Membership,
      on: membership.organization_id == chat_room.organization_id
    )
    |> where([chat_room, membership], membership.user_id == ^user.id and chat_room.id == ^id)
    |> preload(^chat_room_preloads())
    |> select([chat_room, _membership], chat_room)
    |> Repo.one()
  end

  def create_chat_room(%Scope{} = scope, attrs) do
    organization_id = Scope.organization_id!(scope)

    case do_create_chat_room(organization_id, attrs) do
      {:ok, chat_room} -> {:ok, get_chat_room!(scope, chat_room.id)}
      {:error, _reason} = error -> error
    end
  end

  def create_subagent_chat_room(%ChatRoom{} = parent_room, %Agent{} = agent, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:parent_id, parent_room.id)
      |> Map.put(:agent_ids, [agent.id])
      |> Map.put_new(:active_agent_id, agent.id)

    with true <- agent.organization_id == parent_room.organization_id || {:error, :invalid_agent},
         {:ok, chat_room} <- do_create_chat_room(parent_room.organization_id, attrs) do
      {:ok, preload_chat_room(chat_room)}
    end
  end

  def change_chat_room(%ChatRoom{} = chat_room, attrs \\ %{}) do
    chat_room
    |> prepare_chat_room_for_form()
    |> ChatRoom.changeset(attrs)
  end

  def delete_chat_room(%Scope{} = scope, %ChatRoom{} = chat_room) do
    ensure_user_owns_chat_room!(scope, chat_room)
    cancel_active_room_streams(chat_room.id)
    Repo.delete(chat_room)
  end

  def add_agent_to_room(%Scope{} = scope, %ChatRoom{} = chat_room, agent_id, opts \\ []) do
    chat_room = ensure_loaded_chat_room(scope, chat_room)
    agent = get_agent_for_room!(scope, agent_id)
    is_active = Keyword.get(opts, :is_active, false)

    Multi.new()
    |> maybe_clear_active(chat_room, is_active)
    |> Multi.insert(
      :chat_room_agent,
      ChatRoomAgent.changeset(%ChatRoomAgent{}, %{
        chat_room_id: chat_room.id,
        agent_id: agent.id,
        is_active: is_active
      })
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{chat_room_agent: chat_room_agent}} ->
        {:ok, Repo.preload(chat_room_agent, agent: :provider)}

      {:error, :chat_room_agent, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def remove_agent_from_room(%Scope{} = scope, %ChatRoom{} = chat_room, agent_id) do
    ensure_user_owns_chat_room!(scope, chat_room)

    chat_room_agent =
      Repo.get_by!(ChatRoomAgent, chat_room_id: chat_room.id, agent_id: agent_id)

    Repo.delete(chat_room_agent)
  end

  def list_messages(%ChatRoom{} = chat_room) do
    Message
    |> where([message], message.chat_room_id == ^chat_room.id)
    |> order_by([message], asc: message.position)
    |> preload(^message_preloads())
    |> Repo.all()
  end

  def get_message_by_id(id) do
    Message
    |> preload(^message_preloads())
    |> Repo.get(id)
  end

  def get_tool_message(parent_message_id, tool_call_id) do
    Message
    |> where(
      [message],
      message.parent_message_id == ^parent_message_id and message.tool_call_id == ^tool_call_id
    )
    |> preload(^message_preloads())
    |> Repo.one()
  end

  def create_message(%ChatRoom{} = chat_room, attrs) do
    Repo.transaction(fn ->
      lock_chat_room!(chat_room.id)

      attrs =
        attrs
        |> ensure_message_position(chat_room.id)

      case %Message{chat_room_id: chat_room.id}
           |> Message.changeset(attrs)
           |> Repo.insert() do
        {:ok, message} ->
          touch_chat_room(chat_room)
          message

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, message} ->
        {:ok, Repo.preload(message, message_preloads())}

      {:error, _reason} = error ->
        error
    end
  end

  def update_message(%Message{} = message, attrs) do
    message
    |> Message.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, message} -> {:ok, Repo.preload(message, message_preloads())}
      {:error, _} = error -> error
    end
  end

  def start_stream(%ChatRoom{} = chat_room, messages, %Message{} = message, opts \\ [])
      when is_list(messages) do
    DynamicSupervisor.start_child(
      App.Chat.StreamSupervisor,
      {App.Chat.StreamWorker,
       chat_room: chat_room,
       messages: messages,
       message_id: message.id,
       agent_id: message.agent_id,
       content: message.content || "",
       thinking: Message.thinking(message) || "",
       tool_responses: Message.tool_responses(message),
       tool_call_turns: Message.tool_call_turns(message),
       metadata: message.metadata || %{},
       run_opts:
         Keyword.take(opts, [:thinking_mode, :extra_system_prompt, :extra_tools, :alloy_context])}
    )
  end

  def delete_tool_messages(%Message{id: message_id}) do
    from(message in Message, where: message.parent_message_id == ^message_id)
    |> Repo.delete_all()
  end

  def cancel_stream(message_id) do
    App.Chat.StreamWorker.cancel(message_id)
  end

  def stream_running?(message_id) do
    case Registry.lookup(App.Chat.StreamRegistry, message_id) do
      [{_pid, _value}] -> true
      [] -> false
    end
  end

  def subscribe_chat_room(%ChatRoom{id: chat_room_id}), do: subscribe_chat_room(chat_room_id)

  def subscribe_chat_room(chat_room_id) do
    Phoenix.PubSub.subscribe(App.PubSub, chat_room_topic(chat_room_id))
  end

  def unsubscribe_chat_room(%ChatRoom{id: chat_room_id}), do: unsubscribe_chat_room(chat_room_id)

  def unsubscribe_chat_room(chat_room_id) do
    Phoenix.PubSub.unsubscribe(App.PubSub, chat_room_topic(chat_room_id))
  end

  def broadcast_chat_room(%ChatRoom{id: chat_room_id}, message),
    do: broadcast_chat_room(chat_room_id, message)

  def broadcast_chat_room(chat_room_id, message) do
    Phoenix.PubSub.broadcast(App.PubSub, chat_room_topic(chat_room_id), message)
  end

  def broadcast_chat_room_from(%ChatRoom{id: chat_room_id}, from_pid, message),
    do: broadcast_chat_room_from(chat_room_id, from_pid, message)

  def broadcast_chat_room_from(chat_room_id, from_pid, message) do
    Phoenix.PubSub.broadcast_from(App.PubSub, from_pid, chat_room_topic(chat_room_id), message)
  end

  def chat_room_topic(chat_room_id), do: "chat_room:" <> chat_room_id

  @doc """
  Sets the active agent for a chat room, clearing the active flag from all others.
  """
  def set_active_agent(%ChatRoom{id: chat_room_id} = _chat_room, agent_id) do
    Multi.new()
    |> Multi.update_all(
      :clear_active,
      from(cra in ChatRoomAgent, where: cra.chat_room_id == ^chat_room_id),
      set: [is_active: false]
    )
    |> Multi.update_all(
      :set_active,
      from(cra in ChatRoomAgent,
        where: cra.chat_room_id == ^chat_room_id and cra.agent_id == ^agent_id
      ),
      set: [is_active: true]
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def send_message(%Scope{} = scope, %ChatRoom{} = chat_room, content) do
    chat_room = ensure_loaded_chat_room(scope, chat_room)
    chat_orchestrator().send_message(scope, chat_room, content)
  end

  def find_subagent_report(%ChatRoom{} = chat_room, subagent_id) when is_binary(subagent_id) do
    get_subagent_chat_room(chat_room, subagent_id)
    |> case do
      %ChatRoom{} = child_room -> latest_assistant_message(child_room)
      nil -> nil
    end
  end

  def wait_for_subagent_report(%ChatRoom{} = chat_room, subagent_id, timeout_ms \\ 60_000)
      when is_binary(subagent_id) and is_integer(timeout_ms) and timeout_ms >= 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_subagent_report(chat_room, subagent_id, deadline)
  end

  def get_subagent_chat_room(%ChatRoom{} = parent_room, subagent_id)
      when is_binary(subagent_id) do
    ChatRoom
    |> where(
      [chat_room],
      chat_room.organization_id == ^parent_room.organization_id and
        chat_room.parent_id == ^parent_room.id and chat_room.id == ^subagent_id
    )
    |> preload(^chat_room_preloads())
    |> Repo.one()
  end

  def latest_assistant_message(%ChatRoom{} = chat_room) do
    chat_room
    |> list_messages()
    |> Enum.filter(&(&1.role == "assistant"))
    |> List.last()
  end

  def room_stream_running?(%ChatRoom{} = chat_room) do
    chat_room
    |> list_messages()
    |> Enum.any?(fn message ->
      message.role == "assistant" and message.status in [:pending, :streaming] and
        stream_running?(message.id)
    end)
  end

  def start_parent_followup_stream(
        %ChatRoom{} = parent_room,
        subagent_id,
        extra_system_prompt \\ nil
      )
      when is_binary(subagent_id) do
    parent_room = preload_chat_room(parent_room)
    messages = list_messages(parent_room)

    with {:ok, agent} <- active_agent_for_room(parent_room),
         {:ok, placeholder_message} <-
           create_message(parent_room, %{
             role: "assistant",
             content: nil,
             status: :pending,
             agent_id: agent.id,
             metadata: %{
               "subagent_followup" => true,
               "subagent_room_id" => subagent_id
             }
           }),
         {:ok, stream_pid} <-
           start_stream(
             parent_room,
             messages,
             placeholder_message,
             followup_stream_opts(agent, extra_system_prompt)
           ) do
      broadcast_chat_room(parent_room.id, {:agent_message_created, placeholder_message})
      {:ok, stream_pid}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp chat_room_preloads do
    message_query =
      from message in Message,
        order_by: [asc: message.position],
        preload: ^message_preloads()

    [
      :parent,
      chat_room_agents: [agent: :provider],
      agents: [:provider],
      messages: message_query
    ]
  end

  defp message_preloads do
    tool_message_query =
      from tool_message in Message,
        where: tool_message.role == "tool",
        order_by: [asc: tool_message.position]

    [:agent, tool_messages: tool_message_query]
  end

  defp fetch_agents(organization_id, agent_ids, %Ecto.Changeset{} = changeset) do
    agents =
      Repo.all(
        from agent in Agent,
          where: agent.organization_id == ^organization_id and agent.id in ^agent_ids,
          preload: [:provider]
      )

    if length(agents) == length(agent_ids) do
      ordered_agents =
        Enum.sort_by(agents, fn agent ->
          Enum.find_index(agent_ids, &(&1 == agent.id))
        end)

      {:ok, ordered_agents}
    else
      {:error,
       Ecto.Changeset.add_error(changeset, :agent_ids, "must belong to the current organization")}
    end
  end

  defp insert_chat_room_agents(repo, chat_room, agents, active_id) do
    Enum.reduce_while(agents, {:ok, []}, fn agent, {:ok, memberships} ->
      params = %{
        chat_room_id: chat_room.id,
        agent_id: agent.id,
        is_active: agent.id == active_id
      }

      case %ChatRoomAgent{} |> ChatRoomAgent.changeset(params) |> repo.insert() do
        {:ok, chat_room_agent} ->
          {:cont, {:ok, [chat_room_agent | memberships]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, memberships} -> {:ok, Enum.reverse(memberships)}
      {:error, _} = error -> error
    end
  end

  defp maybe_clear_active(multi, _chat_room, false), do: multi

  defp maybe_clear_active(multi, %ChatRoom{id: chat_room_id}, true) do
    Multi.update_all(
      multi,
      :clear_existing_active,
      from(chat_room_agent in ChatRoomAgent,
        where: chat_room_agent.chat_room_id == ^chat_room_id
      ),
      set: [is_active: false]
    )
  end

  defp touch_chat_room(%ChatRoom{id: chat_room_id}) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(chat_room in ChatRoom, where: chat_room.id == ^chat_room_id),
      set: [updated_at: now]
    )
  end

  defp lock_chat_room!(chat_room_id) do
    Repo.one!(
      from(chat_room in ChatRoom,
        where: chat_room.id == ^chat_room_id,
        lock: "FOR UPDATE",
        select: chat_room.id
      )
    )
  end

  defp ensure_message_position(attrs, chat_room_id) when is_map(attrs) do
    case message_position(attrs) do
      nil ->
        put_message_position(attrs, next_message_position(chat_room_id))

      position when is_integer(position) and position > 0 ->
        put_message_position(attrs, next_available_position(chat_room_id, position))

      _other ->
        attrs
    end
  end

  defp ensure_message_position(attrs, _chat_room_id), do: attrs

  defp message_position(attrs) when is_map(attrs),
    do: Map.get(attrs, :position) || Map.get(attrs, "position")

  defp put_message_position(attrs, position) when is_map(attrs) do
    if Map.has_key?(attrs, "position") do
      Map.put(attrs, "position", position)
    else
      Map.put(attrs, :position, position)
    end
  end

  defp next_available_position(chat_room_id, minimum_position) do
    from(
      message in Message,
      where: message.chat_room_id == ^chat_room_id and message.position >= ^minimum_position,
      order_by: [asc: message.position],
      select: message.position
    )
    |> Repo.all()
    |> Enum.reduce_while(minimum_position, fn position, expected_position ->
      cond do
        position == expected_position ->
          {:cont, expected_position + 1}

        position > expected_position ->
          {:halt, expected_position}

        true ->
          {:cont, expected_position}
      end
    end)
  end

  defp next_message_position(%ChatRoom{id: chat_room_id}), do: next_message_position(chat_room_id)

  defp next_message_position(chat_room_id) do
    from(
      message in Message,
      where: message.chat_room_id == ^chat_room_id,
      select: coalesce(max(message.position), 0) + 1
    )
    |> Repo.one()
  end

  defp prepare_chat_room_for_form(%ChatRoom{} = chat_room) do
    if Ecto.assoc_loaded?(chat_room.chat_room_agents) do
      active_agent_id =
        case Enum.find(chat_room.chat_room_agents, & &1.is_active) ||
               List.first(chat_room.chat_room_agents) do
          nil -> nil
          chat_room_agent -> chat_room_agent.agent_id
        end

      %{
        chat_room
        | agent_ids: Enum.map(chat_room.chat_room_agents, & &1.agent_id),
          active_agent_id: active_agent_id
      }
    else
      chat_room
    end
  end

  defp ensure_loaded_chat_room(%Scope{} = scope, %ChatRoom{} = chat_room),
    do: get_chat_room!(scope, chat_room.id)

  defp ensure_user_owns_chat_room!(%Scope{} = scope, %ChatRoom{organization_id: organization_id}) do
    if organization_id != Scope.organization_id!(scope) do
      raise Ecto.NoResultsError, query: ChatRoom
    end
  end

  defp get_agent_for_room!(%Scope{} = scope, agent_id) do
    Repo.one!(
      from agent in Agent,
        where: agent.organization_id == ^Scope.organization_id!(scope) and agent.id == ^agent_id,
        preload: [:provider]
    )
  end

  defp cancel_active_room_streams(chat_room_id) do
    Message
    |> where(
      [message],
      message.chat_room_id == ^chat_room_id and message.role == "assistant" and
        message.status in [:pending, :streaming]
    )
    |> select([message], message.id)
    |> Repo.all()
    |> Enum.each(fn message_id ->
      case cancel_stream(message_id) do
        :ok -> :ok
        {:error, :not_found} -> :ok
        {:error, _reason} -> :ok
      end
    end)
  end

  defp do_create_chat_room(organization_id, attrs) do
    changeset =
      %ChatRoom{organization_id: organization_id}
      |> ChatRoom.changeset(attrs)
      |> validate_parent_room(organization_id)

    with %{valid?: true} <- changeset,
         agent_ids <- Ecto.Changeset.get_field(changeset, :agent_ids, []),
         active_id <-
           Ecto.Changeset.get_field(changeset, :active_agent_id) || List.first(agent_ids) do
      if agent_ids == [] do
        Repo.insert(changeset)
      else
        case fetch_agents(organization_id, agent_ids, changeset) do
          {:ok, agents} ->
            Multi.new()
            |> Multi.insert(:chat_room, changeset)
            |> Multi.run(:chat_room_agents, fn repo, %{chat_room: chat_room} ->
              insert_chat_room_agents(repo, chat_room, agents, active_id)
            end)
            |> Repo.transaction()
            |> case do
              {:ok, %{chat_room: chat_room}} -> {:ok, chat_room}
              {:error, :chat_room, changeset, _changes} -> {:error, changeset}
              {:error, :chat_room_agents, changeset, _changes} -> {:error, changeset}
            end

          {:error, _reason} = error ->
            error
        end
      end
    else
      %{valid?: false} -> {:error, changeset}
    end
  end

  defp validate_parent_room(changeset, organization_id) do
    case Ecto.Changeset.get_field(changeset, :parent_id) do
      nil ->
        changeset

      parent_id ->
        if Repo.exists?(
             from chat_room in ChatRoom,
               where: chat_room.id == ^parent_id and chat_room.organization_id == ^organization_id
           ) do
          changeset
        else
          Ecto.Changeset.add_error(
            changeset,
            :parent_id,
            "must belong to the current organization"
          )
        end
    end
  end

  defp do_wait_for_subagent_report(%ChatRoom{} = chat_room, subagent_id, deadline) do
    case get_subagent_chat_room(chat_room, subagent_id) do
      nil ->
        {:error, "Unknown subagent_id: #{subagent_id}"}

      child_room ->
        case latest_assistant_message(child_room) do
          %Message{status: status} = report when status in [:completed, :error] ->
            if stream_running?(report.id) do
              wait_for_subagent_again(chat_room, subagent_id, deadline)
            else
              {:ok, report}
            end

          _other ->
            wait_for_subagent_again(chat_room, subagent_id, deadline)
        end
    end
  end

  defp wait_for_subagent_again(chat_room, subagent_id, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      Process.sleep(250)
      do_wait_for_subagent_report(chat_room, subagent_id, deadline)
    end
  end

  defp active_agent_for_room(%ChatRoom{chat_room_agents: chat_room_agents}) do
    case Enum.find(chat_room_agents, & &1.is_active) || List.first(chat_room_agents) do
      %{agent: %Agent{} = agent} -> {:ok, agent}
      _other -> {:error, :no_active_agent}
    end
  end

  defp followup_stream_opts(agent, extra_system_prompt) do
    [thinking_mode: thinking_mode(agent)]
    |> maybe_put_extra_system_prompt(extra_system_prompt)
  end

  defp maybe_put_extra_system_prompt(opts, prompt) when prompt in [nil, ""], do: opts

  defp maybe_put_extra_system_prompt(opts, prompt),
    do: Keyword.put(opts, :extra_system_prompt, prompt)

  defp thinking_mode(%Agent{extra_params: extra_params}) when is_map(extra_params) do
    cond do
      Map.get(extra_params, "thinking") == "enabled" ->
        "enabled"

      Map.get(extra_params, :thinking) == "enabled" ->
        "enabled"

      Map.get(extra_params, "reasoning_effort") in ["minimal", "low", "medium", "high", "xhigh"] ->
        "enabled"

      Map.get(extra_params, :reasoning_effort) in ["minimal", "low", "medium", "high", "xhigh"] ->
        "enabled"

      true ->
        "disabled"
    end
  end

  defp thinking_mode(_agent), do: "disabled"

  @doc """
  Returns a lightweight list of chat rooms for the sidebar.

  Each row includes:
  - `id`
  - `title`
  - `updated_at`
  - `loading` - true while the room has a pending or streaming assistant message
  - `gateway_linked` - true when the room is linked to a gateway channel

  Limited to 30 most recent.
  """
  def list_chat_rooms_for_sidebar(%Scope{} = scope) do
    chat_rooms =
      ChatRoom
      |> where([cr], cr.organization_id == ^Scope.organization_id!(scope))
      |> order_by([cr], desc: cr.updated_at)
      |> select([cr], map(cr, [:id, :title, :updated_at]))
      |> limit(30)
      |> Repo.all()

    loading_ids = sidebar_loading_chat_room_ids(chat_rooms)
    gateway_linked_ids = sidebar_gateway_linked_chat_room_ids(chat_rooms)

    Enum.map(chat_rooms, fn chat_room ->
      chat_room
      |> Map.put(:loading, MapSet.member?(loading_ids, chat_room.id))
      |> Map.put(:gateway_linked, MapSet.member?(gateway_linked_ids, chat_room.id))
    end)
  end

  @doc """
  Updates just the title of a chat room. Used by the auto-title tool.
  """
  def update_chat_room_title(%ChatRoom{} = chat_room, title) when is_binary(title) do
    case normalize_chat_room_title(title) do
      nil ->
        {:error, :blank_title}

      normalized_title when normalized_title == chat_room.title ->
        {:ok, chat_room}

      normalized_title ->
        chat_room
        |> Ecto.Changeset.change(%{title: normalized_title})
        |> Ecto.Changeset.validate_length(:title, max: 160)
        |> Repo.update()
    end
  end

  def update_chat_room_title(chat_room_id, title) when is_binary(chat_room_id) do
    case Repo.get(ChatRoom, chat_room_id) do
      nil -> {:error, :not_found}
      chat_room -> update_chat_room_title(chat_room, title)
    end
  end

  defp normalize_chat_room_title(title) do
    case String.trim(title) do
      "" -> nil
      normalized_title -> normalized_title
    end
  end

  defp sidebar_loading_chat_room_ids([]), do: MapSet.new()

  defp sidebar_loading_chat_room_ids(chat_rooms) do
    chat_room_ids = Enum.map(chat_rooms, & &1.id)

    Message
    |> where(
      [message],
      message.chat_room_id in ^chat_room_ids and message.role == "assistant" and
        message.status in [:pending, :streaming]
    )
    |> distinct([message], message.chat_room_id)
    |> select([message], message.chat_room_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp sidebar_gateway_linked_chat_room_ids([]), do: MapSet.new()

  defp sidebar_gateway_linked_chat_room_ids(chat_rooms) do
    chat_room_ids = Enum.map(chat_rooms, & &1.id)

    from(channel in App.Gateways.Channel,
      where: channel.chat_room_id in ^chat_room_ids,
      distinct: channel.chat_room_id,
      select: channel.chat_room_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp chat_orchestrator, do: Application.get_env(:app, :chat_orchestrator, App.Chat.Orchestrator)
end
