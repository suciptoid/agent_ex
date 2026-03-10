defmodule AppWeb.ChatLive.Show do
  use AppWeb, :live_view

  alias App.Chat

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:chat_room, nil)
     |> assign_message_form(%{"content" => ""})
     |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
     |> stream(:messages, [])}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    {:noreply, load_chat_room(socket, id)}
  end

  @impl true
  def handle_event("validate", %{"message" => message_params}, socket) do
    {:noreply, assign_message_form(socket, message_params)}
  end

  def handle_event("send", %{"message" => %{"content" => content} = message_params}, socket) do
    content = String.trim(content || "")

    if content == "" do
      {:noreply,
       socket
       |> assign_message_form(message_params)
       |> put_flash(:error, "Message cannot be blank")}
    else
      case Chat.send_message(socket.assigns.current_scope, socket.assigns.chat_room, content) do
        {:ok, _assistant_message} ->
          {:noreply,
           socket
           |> load_chat_room(socket.assigns.chat_room.id)
           |> assign_message_form(%{"content" => ""})}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign_message_form(message_params)
           |> put_flash(:error, error_message(reason))}
      end
    end
  end

  def user_message?(message), do: message.role == "user"

  def speaker_name(%{role: "user"}), do: "You"
  def speaker_name(%{agent: %{name: name}}), do: name
  def speaker_name(_message), do: "Assistant"

  def message_icon(%{role: "user"}), do: "hero-user"
  def message_icon(%{role: "assistant"}), do: "hero-cpu-chip"
  def message_icon(%{role: "system"}), do: "hero-command-line"
  def message_icon(_message), do: "hero-wrench-screwdriver"

  defp load_chat_room(socket, id) do
    chat_room = Chat.get_chat_room!(socket.assigns.current_scope, id)
    messages = Chat.list_messages(chat_room)

    socket
    |> assign(:chat_room, chat_room)
    |> assign(:page_title, chat_room.title)
    |> stream(:messages, messages, reset: true)
  end

  defp assign_message_form(socket, params) do
    assign(socket, :message_form, to_form(params, as: :message))
  end

  defp error_message(%{message: message}) when is_binary(message), do: message
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason) when is_atom(reason), do: Phoenix.Naming.humanize(to_string(reason))
  defp error_message(reason), do: inspect(reason)
end
