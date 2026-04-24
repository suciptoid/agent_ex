defmodule AppWeb.ChatLive.All do
  use AppWeb, :live_view

  alias App.Chat

  @tabs [:all, :archived, :task]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "All Chats")
     |> assign(:selected_tab, :all)
     |> assign(:chat_rooms, [])
     |> assign(:tab_counts, %{})
     |> assign(:all_chat_rooms, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    selected_tab = parse_tab(params["tab"])

    {:noreply,
     socket
     |> assign(:selected_tab, selected_tab)
     |> load_chat_rooms()}
  end

  @impl true
  def handle_event("delete-chat-room", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    socket =
      case Chat.get_chat_room(scope, id) do
        nil ->
          socket
          |> load_chat_rooms()
          |> put_flash(:error, "Conversation not found.")

        chat_room ->
          case Chat.delete_chat_room(scope, chat_room) do
            {:ok, _chat_room} ->
              socket
              |> load_chat_rooms()
              |> put_flash(:info, "Conversation deleted.")

            {:error, _reason} ->
              socket
              |> load_chat_rooms()
              |> put_flash(:error, "Failed to delete conversation.")
          end
      end

    {:noreply, socket}
  end

  def handle_event("archive-chat-room", %{"id" => id}, socket) do
    {:noreply, update_chat_room(socket, id, &Chat.archive_chat_room/2, "Conversation archived.")}
  end

  def handle_event("unarchive-chat-room", %{"id" => id}, socket) do
    {:noreply,
     update_chat_room(
       socket,
       id,
       &Chat.unarchive_chat_room/2,
       "Conversation restored to general chats."
     )}
  end

  defp update_chat_room(socket, id, action, success_message) do
    scope = socket.assigns.current_scope

    case Chat.get_chat_room(scope, id) do
      nil ->
        socket
        |> load_chat_rooms()
        |> put_flash(:error, "Conversation not found.")

      chat_room ->
        case action.(scope, chat_room) do
          {:ok, _chat_room} ->
            socket
            |> load_chat_rooms()
            |> put_flash(:info, success_message)

          {:error, _reason} ->
            socket
            |> load_chat_rooms()
            |> put_flash(:error, "Failed to update conversation.")
        end
    end
  end

  defp load_chat_rooms(socket) do
    all_chat_rooms = Chat.list_chat_room_summaries(socket.assigns.current_scope)

    socket
    |> assign(:all_chat_rooms, all_chat_rooms)
    |> assign(:tab_counts, tab_counts(all_chat_rooms))
    |> assign(:chat_rooms, filter_chat_rooms(all_chat_rooms, socket.assigns.selected_tab))
  end

  defp parse_tab(nil), do: :all

  defp parse_tab(tab) when is_binary(tab) do
    parsed =
      try do
        String.to_existing_atom(tab)
      rescue
        ArgumentError -> :all
      end

    if parsed in @tabs, do: parsed, else: :all
  end

  defp filter_chat_rooms(chat_rooms, :all), do: chat_rooms

  defp filter_chat_rooms(chat_rooms, :archived) do
    Enum.filter(chat_rooms, &(&1.type == :archived))
  end

  defp filter_chat_rooms(chat_rooms, :task) do
    Enum.filter(chat_rooms, &(&1.type == :task))
  end

  defp tab_counts(chat_rooms) do
    %{
      all: length(chat_rooms),
      archived: Enum.count(chat_rooms, &(&1.type == :archived)),
      task: Enum.count(chat_rooms, &(&1.type == :task))
    }
  end

  def tabs do
    [
      %{id: :all, label: "All"},
      %{id: :archived, label: "Archived"},
      %{id: :task, label: "Task"}
    ]
  end

  def chat_room_type_label(:general), do: "General"
  def chat_room_type_label(:archived), do: "Archived"
  def chat_room_type_label(:task), do: "Task"
  def chat_room_type_label(:gateway), do: "Gateway"

  def chat_room_type_classes(:general),
    do: "border-emerald-500/20 bg-emerald-500/10 text-emerald-700"

  def chat_room_type_classes(:archived), do: "border-border bg-muted text-muted-foreground"
  def chat_room_type_classes(:task), do: "border-violet-500/20 bg-violet-500/10 text-violet-700"
  def chat_room_type_classes(:gateway), do: "border-primary/20 bg-primary/10 text-primary"

  def action_available?(:archive, %{type: type}), do: type in [:general, :gateway]
  def action_available?(:unarchive, %{type: :archived}), do: true
  def action_available?(_action, _chat_room), do: false

  def chat_room_title(%{title: title}) when is_binary(title) and title != "", do: title
  def chat_room_title(_chat_room), do: "Untitled chat"
end
