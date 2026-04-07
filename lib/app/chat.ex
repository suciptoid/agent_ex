defmodule App.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias App.Agents.Agent
  alias App.Chat.{ChatRoom, ChatRoomAgent, Message}
  alias App.Repo
  alias App.Users.Scope

  def list_chat_rooms(%Scope{} = scope) do
    ChatRoom
    |> where([chat_room], chat_room.user_id == ^scope.user.id)
    |> order_by([chat_room], desc: chat_room.updated_at, desc: chat_room.inserted_at)
    |> preload(^chat_room_preloads())
    |> Repo.all()
  end

  def get_chat_room!(%Scope{} = scope, id) do
    ChatRoom
    |> where([chat_room], chat_room.user_id == ^scope.user.id and chat_room.id == ^id)
    |> preload(^chat_room_preloads())
    |> Repo.one!()
  end

  def create_chat_room(%Scope{} = scope, attrs) do
    changeset =
      %ChatRoom{user_id: scope.user.id}
      |> ChatRoom.changeset(attrs)

    with %{valid?: true} <- changeset,
         agent_ids <- Ecto.Changeset.get_field(changeset, :agent_ids, []),
         active_id <-
           Ecto.Changeset.get_field(changeset, :active_agent_id) || List.first(agent_ids) do
      if agent_ids == [] do
        case Repo.insert(changeset) do
          {:ok, chat_room} -> {:ok, get_chat_room!(scope, chat_room.id)}
          {:error, changeset} -> {:error, changeset}
        end
      else
        case fetch_agents(scope, agent_ids, changeset) do
          {:ok, agents} ->
            Multi.new()
            |> Multi.insert(:chat_room, changeset)
            |> Multi.run(:chat_room_agents, fn repo, %{chat_room: chat_room} ->
              insert_chat_room_agents(repo, chat_room, agents, active_id)
            end)
            |> Repo.transaction()
            |> case do
              {:ok, %{chat_room: chat_room}} -> {:ok, get_chat_room!(scope, chat_room.id)}
              {:error, :chat_room, changeset, _changes} -> {:error, changeset}
              {:error, :chat_room_agents, changeset, _changes} -> {:error, changeset}
            end

          {:error, changeset} ->
            {:error, changeset}
        end
      end
    else
      %{valid?: false} -> {:error, changeset}
    end
  end

  def change_chat_room(%ChatRoom{} = chat_room, attrs \\ %{}) do
    chat_room
    |> prepare_chat_room_for_form()
    |> ChatRoom.changeset(attrs)
  end

  def delete_chat_room(%Scope{} = scope, %ChatRoom{} = chat_room) do
    ensure_user_owns_chat_room!(scope, chat_room)
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
    %Message{chat_room_id: chat_room.id, position: next_message_position(chat_room)}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        touch_chat_room(chat_room)
        {:ok, Repo.preload(message, message_preloads())}

      {:error, _} = error ->
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
       run_opts: Keyword.take(opts, [:reasoning_effort])}
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

  defp chat_room_preloads do
    message_query =
      from message in Message,
        order_by: [asc: message.position],
        preload: ^message_preloads()

    [chat_room_agents: [agent: :provider], agents: [:provider], messages: message_query]
  end

  defp message_preloads do
    tool_message_query =
      from tool_message in Message,
        where: tool_message.role == "tool",
        order_by: [asc: tool_message.position]

    [:agent, tool_messages: tool_message_query]
  end

  defp fetch_agents(%Scope{} = scope, agent_ids, %Ecto.Changeset{} = changeset) do
    agents =
      Repo.all(
        from agent in Agent,
          where: agent.user_id == ^scope.user.id and agent.id in ^agent_ids,
          preload: [:provider]
      )

    if length(agents) == length(agent_ids) do
      ordered_agents =
        Enum.sort_by(agents, fn agent ->
          Enum.find_index(agent_ids, &(&1 == agent.id))
        end)

      {:ok, ordered_agents}
    else
      {:error, Ecto.Changeset.add_error(changeset, :agent_ids, "must belong to the current user")}
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

  defp next_message_position(%ChatRoom{id: chat_room_id}) do
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

  defp ensure_user_owns_chat_room!(%Scope{} = scope, %ChatRoom{user_id: user_id}) do
    if user_id != scope.user.id do
      raise Ecto.NoResultsError, query: ChatRoom
    end
  end

  defp get_agent_for_room!(%Scope{} = scope, agent_id) do
    Repo.one!(
      from agent in Agent,
        where: agent.user_id == ^scope.user.id and agent.id == ^agent_id,
        preload: [:provider]
    )
  end

  @doc """
  Returns a lightweight list of chat rooms for the sidebar.

  Each row includes:
  - `id`
  - `title`
  - `updated_at`
  - `loading` - true while the room has a pending or streaming assistant message

  Limited to 30 most recent.
  """
  def list_chat_rooms_for_sidebar(%Scope{} = scope) do
    chat_rooms =
      ChatRoom
      |> where([cr], cr.user_id == ^scope.user.id)
      |> order_by([cr], desc: cr.updated_at)
      |> select([cr], map(cr, [:id, :title, :updated_at]))
      |> limit(30)
      |> Repo.all()

    loading_ids = sidebar_loading_chat_room_ids(chat_rooms)

    Enum.map(chat_rooms, fn chat_room ->
      Map.put(chat_room, :loading, MapSet.member?(loading_ids, chat_room.id))
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

  defp chat_orchestrator, do: Application.get_env(:app, :chat_orchestrator, App.Chat.Orchestrator)
end
