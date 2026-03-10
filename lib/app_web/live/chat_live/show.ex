defmodule AppWeb.ChatLive.Show do
  use AppWeb, :live_view

  require Logger

  alias App.Chat
  alias App.Chat.Orchestrator

  # Debounce: write to DB every N tokens during streaming
  @stream_db_write_every 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:chat_room, nil)
     |> assign(:agent_message_streams, %{})
     |> assign(:streaming_message_id, nil)
     |> assign(:streaming_message_agent, nil)
     |> assign(:streaming_message_inserted_at, nil)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_token_count, 0)
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
          active_agent = active_agent_for_room(chat_room)
          lv_pid = self()

          case Chat.create_message(chat_room, %{
                 role: "assistant",
                 content: "",
                 status: "requesting",
                 agent_id: active_agent && active_agent.id
               }) do
            {:ok, placeholder_message} ->
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
               |> assign(:streaming_message_id, placeholder_message.id)
               |> assign(:streaming_message_agent, placeholder_message.agent)
               |> assign(:streaming_message_inserted_at, placeholder_message.inserted_at)
               |> assign(:streaming_content, "")
               |> assign(:streaming_token_count, 0)
               |> assign(:streaming_task_ref, task.ref)
               |> assign_message_form(%{"content" => ""})}

            {:error, _reason} ->
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
               |> assign(:streaming_message_agent, nil)
               |> assign(:streaming_message_inserted_at, nil)
               |> assign(:streaming_content, "")
               |> assign(:streaming_token_count, 0)
               |> assign(:streaming_task_ref, task.ref)
               |> assign_message_form(%{"content" => ""})}
          end

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
    new_content = current <> token
    new_count = socket.assigns.streaming_token_count + 1

    socket =
      socket
      |> assign(:streaming_content, new_content)
      |> assign(:streaming_token_count, new_count)

    # Update the placeholder message in the stream for real-time display
    socket =
      if socket.assigns.streaming_message_id do
        placeholder = %{
          id: socket.assigns.streaming_message_id,
          role: "assistant",
          content: new_content,
          status: "streaming",
          metadata: %{},
          agent: socket.assigns.streaming_message_agent,
          inserted_at: socket.assigns.streaming_message_inserted_at || DateTime.utc_now(),
          chat_room_id: socket.assigns.chat_room.id
        }

        stream_insert(socket, :messages, placeholder)
      else
        socket
      end

    # Debounce: write to DB every N tokens
    if rem(new_count, @stream_db_write_every) == 0 && socket.assigns.streaming_message_id do
      maybe_update_streaming_message(
        socket.assigns.streaming_message_id,
        new_content,
        "streaming"
      )
    end

    {:noreply, socket}
  end

  def handle_info({:agent_message_created, message}, socket) do
    if same_chat_room_message?(socket, message) do
      {:noreply,
       socket
       |> maybe_track_agent_stream(message)
       |> stream_insert(:messages, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:agent_message_stream_chunk, message_id, token}, socket) do
    {:noreply, stream_agent_message_chunk(socket, message_id, token)}
  end

  def handle_info({:agent_message_updated, message}, socket) do
    if same_chat_room_message?(socket, message) do
      {:noreply,
       socket
       |> clear_agent_stream(message.id)
       |> stream_insert(:messages, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:active_agent_changed, _agent_id}, socket) do
    {:noreply, load_chat_room(socket, socket.assigns.chat_room.id)}
  end

  def handle_info({ref, {:stream_done, result}}, socket)
      when socket.assigns.streaming_task_ref == ref do
    Process.demonitor(ref, [:flush])
    chat_room = socket.assigns.chat_room
    streaming_message_id = socket.assigns.streaming_message_id

    socket =
      case result do
        {:ok, %{content: content, agent_id: agent_id, metadata: metadata}} ->
          if streaming_message_id do
            case Chat.get_message_by_id(streaming_message_id) do
              nil ->
                # Placeholder was lost, create fresh message
                case Chat.create_message(chat_room, %{
                       role: "assistant",
                       content: content,
                       agent_id: agent_id,
                       metadata: metadata,
                       status: "completed"
                     }) do
                  {:ok, _} ->
                    socket

                  {:error, reason} ->
                    Logger.error("[ChatLive.Show] Failed to save message: #{inspect(reason)}")

                    put_flash(
                      socket,
                      :error,
                      "Failed to save response: #{changeset_error(reason)}"
                    )
                end

              existing_message ->
                case Chat.update_message(existing_message, %{
                       content: content,
                       agent_id: agent_id,
                       metadata: metadata,
                       status: "completed"
                     }) do
                  {:ok, _} ->
                    Logger.info(
                      "[ChatLive.Show] Updated streamed message #{streaming_message_id}"
                    )

                    socket

                  {:error, reason} ->
                    Logger.error(
                      "[ChatLive.Show] Failed to update streamed message: #{inspect(reason)}"
                    )

                    put_flash(
                      socket,
                      :error,
                      "Failed to save response: #{changeset_error(reason)}"
                    )
                end
            end
          else
            case Chat.create_message(chat_room, %{
                   role: "assistant",
                   content: content,
                   agent_id: agent_id,
                   metadata: metadata,
                   status: "completed"
                 }) do
              {:ok, _} ->
                socket

              {:error, reason} ->
                Logger.error(
                  "[ChatLive.Show] Failed to save streamed message: #{inspect(reason)}"
                )

                put_flash(socket, :error, "Failed to save response: #{changeset_error(reason)}")
            end
          end

        {:error, reason} ->
          if streaming_message_id do
            maybe_update_streaming_message(
              streaming_message_id,
              socket.assigns.streaming_content || "",
              "error"
            )
          end

          put_flash(socket, :error, error_message(reason))
      end

    {:noreply,
     socket
     |> load_chat_room(chat_room.id)
     |> assign(:streaming_message_id, nil)
     |> assign(:streaming_message_agent, nil)
     |> assign(:streaming_message_inserted_at, nil)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_token_count, 0)
     |> assign(:streaming_task_ref, nil)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket)
      when socket.assigns.streaming_task_ref == ref do
    Logger.error("[ChatLive.Show] Streaming task crashed: #{inspect(reason)}")

    if socket.assigns.streaming_message_id do
      maybe_update_streaming_message(
        socket.assigns.streaming_message_id,
        socket.assigns.streaming_content || "",
        "error"
      )
    end

    {:noreply,
     socket
     |> load_chat_room(socket.assigns.chat_room.id)
     |> assign(:streaming_message_id, nil)
     |> assign(:streaming_message_agent, nil)
     |> assign(:streaming_message_inserted_at, nil)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_token_count, 0)
     |> assign(:streaming_task_ref, nil)
     |> put_flash(:error, "The agent encountered an error")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  def user_message?(message), do: message.role == "user"

  def tool_message?(message),
    do: message.role == "tool" or get_in(message.metadata, ["finish_reason"]) == "tool_calls"

  def streaming_message?(%{status: status}), do: status in ["requesting", "streaming"]

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

  defp active_agent_for_room(%{chat_room_agents: agents}) do
    case Enum.find(agents, & &1.is_active) || List.first(agents) do
      %{agent: agent} -> agent
      _ -> nil
    end
  end

  defp active_agent_for_room(_), do: nil

  defp maybe_update_streaming_message(message_id, content, status) do
    case Chat.get_message_by_id(message_id) do
      nil -> :ok
      message -> Chat.update_message(message, %{content: content, status: status})
    end
  end

  defp maybe_track_agent_stream(socket, %{id: id, status: status} = message)
       when status in ["requesting", "streaming"] do
    update(socket, :agent_message_streams, fn streams ->
      Map.put(streams, id, %{
        content: message.content || "",
        token_count: 0,
        inserted_at: message.inserted_at,
        agent: message.agent,
        metadata: message.metadata || %{}
      })
    end)
  end

  defp maybe_track_agent_stream(socket, _message), do: socket

  defp clear_agent_stream(socket, message_id) do
    update(socket, :agent_message_streams, &Map.delete(&1, message_id))
  end

  defp stream_agent_message_chunk(socket, message_id, token) do
    case current_agent_stream(socket, message_id) do
      nil ->
        socket

      stream_state ->
        new_content = stream_state.content <> token
        new_count = stream_state.token_count + 1

        socket =
          update(socket, :agent_message_streams, fn streams ->
            Map.put(streams, message_id, %{
              stream_state
              | content: new_content,
                token_count: new_count
            })
          end)

        placeholder = %{
          id: message_id,
          role: "assistant",
          content: new_content,
          status: "streaming",
          metadata: stream_state.metadata,
          agent: stream_state.agent,
          inserted_at: stream_state.inserted_at || DateTime.utc_now(),
          chat_room_id: socket.assigns.chat_room.id
        }

        socket = stream_insert(socket, :messages, placeholder)

        if rem(new_count, @stream_db_write_every) == 0 do
          maybe_update_streaming_message(message_id, new_content, "streaming")
        end

        socket
    end
  end

  defp current_agent_stream(socket, message_id) do
    case Map.get(socket.assigns.agent_message_streams, message_id) do
      nil ->
        case Chat.get_message_by_id(message_id) do
          %{chat_room_id: chat_room_id} = message
          when chat_room_id == socket.assigns.chat_room.id ->
            %{
              content: message.content || "",
              token_count: 0,
              inserted_at: message.inserted_at,
              agent: message.agent,
              metadata: message.metadata || %{}
            }

          _ ->
            nil
        end

      stream_state ->
        stream_state
    end
  end

  defp same_chat_room_message?(socket, %{chat_room_id: chat_room_id}),
    do: socket.assigns.chat_room && socket.assigns.chat_room.id == chat_room_id

  defp same_chat_room_message?(_socket, _message), do: false

  defp error_message(%{message: message}) when is_binary(message), do: message
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason) when is_atom(reason), do: Phoenix.Naming.humanize(to_string(reason))
  defp error_message(reason), do: inspect(reason)

  defp changeset_error(%Ecto.Changeset{errors: errors}) do
    errors |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end) |> Enum.join(", ")
  end

  defp changeset_error(reason), do: inspect(reason)
end
