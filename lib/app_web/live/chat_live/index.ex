defmodule AppWeb.ChatLive.Index do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Chat
  alias App.Chat.ChatRoom

  @impl true
  def mount(_params, _session, socket) do
    available_agents = Agents.list_agents(socket.assigns.current_scope)
    chat_rooms = Chat.list_chat_rooms(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:available_agents, available_agents)
     |> assign(:chat_room, nil)
     |> assign(:form, nil)
     |> stream_configure(:chat_rooms, dom_id: &"chat-room-#{&1.id}")
     |> stream(:chat_rooms, chat_rooms)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Chat")
    |> assign(:chat_room, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Chat.change_chat_room(%ChatRoom{})

    socket
    |> assign(:page_title, "New Chat")
    |> assign(:chat_room, %ChatRoom{})
    |> assign_form(changeset)
  end

  @impl true
  def handle_event("validate", %{"chat_room" => chat_room_params}, socket) do
    changeset =
      %ChatRoom{}
      |> Chat.change_chat_room(chat_room_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"chat_room" => chat_room_params}, socket) do
    case Chat.create_chat_room(socket.assigns.current_scope, chat_room_params) do
      {:ok, chat_room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Chat room created successfully")
         |> push_navigate(to: ~p"/chat/#{chat_room.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    chat_room = Chat.get_chat_room!(socket.assigns.current_scope, id)
    {:ok, _chat_room} = Chat.delete_chat_room(socket.assigns.current_scope, chat_room)

    {:noreply, stream_delete(socket, :chat_rooms, chat_room)}
  end

  def last_message_preview(%ChatRoom{messages: messages}) do
    case List.last(messages || []) do
      nil ->
        "No messages yet."

      message ->
        content = message.content || ""

        if String.length(content) > 120 do
          String.slice(content, 0, 120) <> "…"
        else
          content
        end
    end
  end

  def agent_count(%ChatRoom{agents: agents}), do: length(agents || [])

  def active_agent_name(%ChatRoom{chat_room_agents: chat_room_agents}) do
    case Enum.find(chat_room_agents, & &1.is_active) || List.first(chat_room_agents) do
      nil -> nil
      chat_room_agent -> chat_room_agent.agent.name
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
