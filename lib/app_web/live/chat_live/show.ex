defmodule AppWeb.ChatLive.Show do
  use AppWeb, :live_view

  require Logger

  alias App.Chat
  alias App.Chat.Orchestrator

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:chat_room, nil)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_agent_name, nil)
     |> assign(:streaming_task_ref, nil)
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
      chat_room = socket.assigns.chat_room

      case Chat.create_message(chat_room, %{role: "user", content: content}) do
        {:ok, _user_message} ->
          messages = Chat.list_messages(chat_room)
          agent_name = commander_agent_name(chat_room)
          lv_pid = self()

          task =
            Task.async(fn ->
              case Orchestrator.stream_message(chat_room, messages, lv_pid) do
                {:ok, result} -> {:stream_done, {:ok, result}}
                {:error, reason} -> {:stream_done, {:error, reason}}
              end
            end)

          {:noreply,
           socket
           |> load_chat_room(chat_room.id)
           |> assign(:streaming_content, "")
           |> assign(:streaming_agent_name, agent_name)
           |> assign(:streaming_task_ref, task.ref)
           |> assign_message_form(%{"content" => ""})}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign_message_form(message_params)
           |> put_flash(:error, "Failed to send: #{changeset_error(changeset)}")}
      end
    end
  end

  @impl true
  def handle_info({:stream_chunk, token}, socket) do
    current = socket.assigns.streaming_content || ""
    {:noreply, assign(socket, :streaming_content, current <> token)}
  end

  def handle_info({ref, {:stream_done, result}}, socket)
      when socket.assigns.streaming_task_ref == ref do
    Process.demonitor(ref, [:flush])
    chat_room = socket.assigns.chat_room

    socket =
      case result do
        {:ok, %{content: content, agent_id: agent_id, metadata: metadata}} ->
          case Chat.create_message(chat_room, %{
                 role: "assistant",
                 content: content,
                 agent_id: agent_id,
                 metadata: metadata
               }) do
            {:ok, _} ->
              Logger.info("[ChatLive.Show] Saved streamed message for room #{chat_room.id}")
              socket

            {:error, reason} ->
              Logger.error("[ChatLive.Show] Failed to save streamed message: #{inspect(reason)}")
              put_flash(socket, :error, "Failed to save response: #{changeset_error(reason)}")
          end

        {:error, reason} ->
          put_flash(socket, :error, error_message(reason))
      end

    {:noreply,
     socket
     |> load_chat_room(chat_room.id)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_agent_name, nil)
     |> assign(:streaming_task_ref, nil)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket)
      when socket.assigns.streaming_task_ref == ref do
    Logger.error("[ChatLive.Show] Streaming task crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:streaming_content, nil)
     |> assign(:streaming_agent_name, nil)
     |> assign(:streaming_task_ref, nil)
     |> put_flash(:error, "The agent encountered an error")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  def user_message?(message), do: message.role == "user"

  def tool_message?(message),
    do: message.role == "tool" or get_in(message.metadata, ["finish_reason"]) == "tool_calls"

  def speaker_name(%{role: "user"}), do: "You"
  def speaker_name(%{agent: %{name: name}}), do: name
  def speaker_name(_message), do: "Assistant"

  def message_icon(%{role: "user"}), do: "hero-user"
  def message_icon(%{role: "assistant"}), do: "hero-cpu-chip"
  def message_icon(%{role: "system"}), do: "hero-command-line"
  def message_icon(%{role: "tool"}), do: "hero-wrench-screwdriver"
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

  defp commander_agent_name(%{chat_room_agents: agents}) do
    case Enum.find(agents, & &1.is_commander) || List.first(agents) do
      %{agent: %{name: name}} -> name
      _ -> "Assistant"
    end
  end

  defp error_message(%{message: message}) when is_binary(message), do: message
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason) when is_atom(reason), do: Phoenix.Naming.humanize(to_string(reason))
  defp error_message(reason), do: inspect(reason)

  defp changeset_error(%Ecto.Changeset{errors: errors}) do
    errors |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end) |> Enum.join(", ")
  end

  defp changeset_error(reason), do: inspect(reason)
end
