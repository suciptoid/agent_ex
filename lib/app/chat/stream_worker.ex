defmodule App.Chat.StreamWorker do
  @moduledoc """
  Runs chat message streaming outside of the LiveView lifecycle.
  """

  use GenServer

  require Logger

  alias App.Chat
  alias App.Chat.Message
  alias App.Chat.Orchestrator

  @stream_db_write_every 10

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :message_id)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  def start_link(opts) do
    message_id = Keyword.fetch!(opts, :message_id)
    GenServer.start_link(__MODULE__, opts, name: via(message_id))
  end

  def cancel(message_id) do
    GenServer.call(via(message_id), :cancel)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
  end

  def via(message_id), do: {:via, Registry, {App.Chat.StreamRegistry, message_id}}

  @impl true
  def init(opts) do
    state = %{
      chat_room: Keyword.fetch!(opts, :chat_room),
      messages: Keyword.fetch!(opts, :messages),
      message_id: Keyword.fetch!(opts, :message_id),
      agent_id: Keyword.get(opts, :agent_id),
      content: Keyword.get(opts, :content, "") || "",
      thinking: Keyword.get(opts, :thinking, "") || "",
      next_tool_position: nil,
      followup_message_position: nil,
      pending_tool_call_ids: [],
      tool_parent_message_id: nil,
      tool_responses: Keyword.get(opts, :tool_responses, []),
      metadata: Keyword.get(opts, :metadata, %{}) || %{},
      run_opts: Keyword.get(opts, :run_opts, []),
      token_count: 0,
      task: nil,
      task_ref: nil
    }

    {:ok, state, {:continue, :start_stream}}
  end

  @impl true
  def handle_continue(:start_stream, state) do
    worker_pid = self()

    task =
      Task.async(fn ->
        callbacks = [
          on_result: fn token -> send(worker_pid, {:stream_chunk, token}) end,
          on_thinking: fn token -> send(worker_pid, {:stream_thinking_chunk, token}) end,
          on_tool_calls: fn tool_call_turn ->
            send(worker_pid, {:stream_tool_calls, tool_call_turn})
          end,
          on_tool_start: fn tool_result ->
            send(worker_pid, {:stream_tool_started, tool_result})
          end,
          on_tool_result: fn tool_result ->
            send(worker_pid, {:stream_tool_result, tool_result})
          end,
          on_title_updated: fn title ->
            send(worker_pid, {:title_updated, title})
          end,
          on_agent_message_created: fn message ->
            broadcast(state.chat_room.id, {:agent_message_created, message})
          end,
          on_agent_message_stream_chunk: fn message_id, token ->
            broadcast(state.chat_room.id, {:agent_message_stream_chunk, message_id, token})
          end,
          on_agent_message_thinking_chunk: fn message_id, token ->
            broadcast(state.chat_room.id, {:agent_message_thinking_chunk, message_id, token})
          end,
          on_agent_message_tool_started: fn message_id, tool_result ->
            broadcast(state.chat_room.id, {:agent_message_tool_started, message_id, tool_result})
          end,
          on_agent_message_tool_result: fn message_id, tool_result ->
            broadcast(state.chat_room.id, {:agent_message_tool_result, message_id, tool_result})
          end,
          on_agent_message_updated: fn message ->
            broadcast(state.chat_room.id, {:agent_message_updated, message})
          end,
          on_active_agent_changed: fn agent_id ->
            broadcast(state.chat_room.id, {:active_agent_changed, agent_id})
          end
        ]

        case Orchestrator.stream_message(
               state.chat_room,
               state.messages,
               callbacks ++ state.run_opts
             ) do
          {:ok, result} -> {:stream_done, {:ok, result}}
          {:error, reason} -> {:stream_done, {:error, reason}}
        end
      end)

    {:noreply, %{state | task: task, task_ref: task.ref}}
  end

  @impl true
  def handle_call(:cancel, _from, %{task: nil} = state) do
    {:reply, {:error, :not_running}, state}
  end

  def handle_call(:cancel, _from, state) do
    state = ensure_followup_message(state, true)
    _ = Task.shutdown(state.task, :brutal_kill)

    persisted? =
      persist_cancel(
        state.chat_room,
        state.message_id,
        state.content,
        state.metadata,
        state.thinking,
        state
      )

    if persisted? do
      broadcast_message_update(state.chat_room.id, state.message_id)
    end

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:stream_chunk, token}, state) do
    state = ensure_followup_message(state, true)
    new_content = append_text(state.content, token)
    new_count = state.token_count + 1

    state = %{state | content: new_content, token_count: new_count}
    broadcast(state.chat_room.id, {:stream_chunk, state.message_id, token})

    if rem(new_count, @stream_db_write_every) == 0 do
      maybe_update_streaming_message(
        state.message_id,
        new_content,
        stream_placeholder_status(new_content),
        build_message_metadata(state.metadata, state.thinking)
      )
    end

    {:noreply, state}
  end

  def handle_info({:stream_thinking_chunk, token}, state) do
    state = ensure_followup_message(state, true)
    state = %{state | thinking: append_text(state.thinking, token)}
    broadcast(state.chat_room.id, {:stream_thinking_chunk, state.message_id, token})
    {:noreply, state}
  end

  def handle_info({:stream_tool_calls, tool_call_turn}, state) do
    case split_assistant_turn(state, tool_call_turn) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.error("[StreamWorker] Failed to split assistant turn: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({:stream_tool_started, tool_result}, state) do
    tool_responses = merge_tool_response(state.tool_responses, tool_result)
    state = %{state | tool_responses: tool_responses}

    case persist_tool_message(state, tool_result) do
      {:ok, state, tool_message} ->
        broadcast_message_update(state.chat_room.id, tool_message.id)
        broadcast(state.chat_room.id, {:stream_tool_started, state.message_id, tool_result})
        {:noreply, state}

      {:error, _reason} ->
        broadcast(state.chat_room.id, {:stream_tool_started, state.message_id, tool_result})
        {:noreply, state}
    end
  end

  def handle_info({:stream_tool_result, tool_result}, state) do
    tool_responses = merge_tool_response(state.tool_responses, tool_result)
    state = %{state | tool_responses: tool_responses}

    state =
      case persist_tool_message(state, tool_result) do
        {:ok, state, tool_message} ->
          broadcast_message_update(state.chat_room.id, tool_message.id)
          broadcast(state.chat_room.id, {:stream_tool_result, state.message_id, tool_result})
          ensure_followup_message(state, false)

        {:error, _reason} ->
          broadcast(state.chat_room.id, {:stream_tool_result, state.message_id, tool_result})
          ensure_followup_message(state, false)
      end

    {:noreply, state}
  end

  def handle_info({:title_updated, title}, state) do
    case Chat.update_chat_room_title(state.chat_room, title) do
      {:ok, chat_room} ->
        if chat_room.title != state.chat_room.title do
          broadcast(state.chat_room.id, {:chatroom_title_updated, chat_room.title})
        end

        {:noreply, %{state | chat_room: chat_room}}

      {:error, :blank_title} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.error("[StreamWorker] Failed to update title: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({ref, {:stream_done, result}}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])
    state = ensure_followup_message(state, true)

    completion_event =
      case result do
        {:ok, %{content: content, agent_id: agent_id, metadata: metadata}} ->
          persist_success(state.chat_room, state.message_id, content, agent_id, metadata, state)
          {:stream_complete, tool_parent_message_id(state), content}

        {:error, reason} ->
          error_text = error_message(reason)
          persist_error(state.chat_room, state.message_id, error_text, state)
          {:stream_error, tool_parent_message_id(state), error_text}
      end

    broadcast_message_update(state.chat_room.id, state.message_id)
    broadcast(state.chat_room.id, completion_event)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    state = ensure_followup_message(state, true)
    error_text = "The agent encountered an error"

    Logger.error(
      "[StreamWorker] Streaming task crashed for message #{state.message_id}: #{inspect(reason)}"
    )

    persist_error(state.chat_room, state.message_id, error_text, state)
    broadcast_message_update(state.chat_room.id, state.message_id)
    broadcast(state.chat_room.id, {:stream_error, tool_parent_message_id(state), error_text})
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp persist_success(chat_room, message_id, content, agent_id, metadata, state) do
    attrs =
      %{
        content: content,
        agent_id: agent_id,
        metadata: metadata,
        status: :completed
      }
      |> maybe_put_position(final_message_position(state))

    persist_message(chat_room, message_id, attrs)
  end

  defp persist_error(chat_room, message_id, error_text, state) do
    metadata =
      build_message_metadata(state.metadata, state.thinking)
      |> Map.put("error", error_text)

    persist_message(
      chat_room,
      message_id,
      %{
        content: error_text,
        status: :error,
        metadata: metadata
      }
      |> maybe_put_position(final_message_position(state))
    )
  end

  defp persist_cancel(chat_room, message_id, content, metadata, thinking, state) do
    cancel_text = "Response cancelled."

    persist_message(
      chat_room,
      message_id,
      %{
        content: blank_to_nil(content) || cancel_text,
        status: :error,
        metadata:
          build_message_metadata(metadata, thinking)
          |> Map.put("error", cancel_text)
          |> Map.put("cancelled", true)
      }
      |> maybe_put_position(final_message_position(state))
    )
  end

  defp persist_message(chat_room, message_id, attrs) do
    case Chat.get_message_by_id(message_id) do
      nil ->
        case Chat.create_message(chat_room, Map.put(attrs, :role, "assistant")) do
          {:ok, _message} ->
            true

          {:error, reason} ->
            Logger.error(
              "[StreamWorker] Failed to persist message #{message_id}: #{inspect(reason)}"
            )

            false
        end

      message ->
        case Chat.update_message(message, attrs) do
          {:ok, _message} ->
            true

          {:error, reason} ->
            Logger.error(
              "[StreamWorker] Failed to update message #{message_id}: #{inspect(reason)}"
            )

            false
        end
    end
  end

  defp maybe_update_streaming_message(message_id, content, status, metadata) do
    case Chat.get_message_by_id(message_id) do
      nil ->
        :ok

      message ->
        Chat.update_message(message, %{
          content: blank_to_nil(content),
          status: status,
          metadata: metadata
        })
    end
  end

  defp broadcast_message_update(chat_room_id, message_id) do
    if message = Chat.get_message_by_id(message_id) do
      broadcast(chat_room_id, {:stream_updated, message})
    end
  end

  defp broadcast(chat_room_id, message) do
    Chat.broadcast_chat_room(chat_room_id, message)
  end

  defp split_assistant_turn(state, tool_call_turn) do
    tool_parent_message_id = state.message_id

    case Chat.get_message_by_id(tool_parent_message_id) do
      nil ->
        {:error, :missing_assistant_message}

      message ->
        completed_position = completed_turn_position(state, message.position)
        next_tool_position = completed_position + 1

        with {:ok, _message} <-
               Chat.update_message(
                 message,
                 tool_call_message_attrs(state, tool_call_turn, completed_position)
               ) do
          broadcast_message_update(state.chat_room.id, tool_parent_message_id)

          {:ok,
           %{
             state
             | content: "",
               thinking: "",
               metadata: carry_forward_metadata(state.metadata),
               token_count: 0,
               next_tool_position: next_tool_position,
               followup_message_position: reserved_message_position(completed_position),
               pending_tool_call_ids:
                 tool_call_turn
                 |> turn_tool_calls()
                 |> Enum.map(&tool_call_id/1)
                 |> Enum.reject(&is_nil/1),
               tool_parent_message_id: tool_parent_message_id,
               tool_responses: [],
               agent_id: message.agent_id || state.agent_id
           }}
        else
          {:error, _reason} = error ->
            error
        end
    end
  end

  defp tool_call_message_attrs(state, tool_call_turn, position) do
    %{
      content: blank_to_nil(turn_content(tool_call_turn)),
      position: position,
      status: :completed,
      metadata: tool_call_message_metadata(state.metadata, state.thinking, tool_call_turn)
    }
  end

  defp create_followup_assistant_message(state, position) do
    Chat.create_message(state.chat_room, %{
      role: "assistant",
      content: nil,
      position: position,
      status: :pending,
      agent_id: state.agent_id,
      metadata: carry_forward_metadata(state.metadata)
    })
  end

  defp ensure_followup_message(state, force?) do
    case maybe_create_followup_message(state, force?) do
      {:ok, state} ->
        state

      {:error, reason} ->
        Logger.error(
          "[StreamWorker] Failed to create follow-up assistant message for #{state.message_id}: #{inspect(reason)}"
        )

        state
    end
  end

  defp maybe_create_followup_message(%{followup_message_position: nil} = state, _force?),
    do: {:ok, state}

  defp maybe_create_followup_message(state, force?) do
    if force? or tool_turn_complete?(state) do
      case create_followup_assistant_message(state, state.followup_message_position) do
        {:ok, next_message} ->
          case switch_stream_message(state.message_id, next_message.id) do
            :ok ->
              broadcast_message_update(state.chat_room.id, next_message.id)

              {:ok,
               %{
                 state
                 | message_id: next_message.id,
                   agent_id: next_message.agent_id || state.agent_id,
                   content: next_message.content || "",
                   thinking: Message.thinking(next_message) || "",
                   metadata: next_message.metadata || %{},
                   token_count: 0,
                   followup_message_position: nil,
                   pending_tool_call_ids: []
               }}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, state}
    end
  end

  defp switch_stream_message(previous_message_id, next_message_id)
       when previous_message_id == next_message_id,
       do: :ok

  defp switch_stream_message(previous_message_id, next_message_id) do
    case Registry.register(App.Chat.StreamRegistry, next_message_id, nil) do
      {:ok, _value} ->
        Registry.unregister(App.Chat.StreamRegistry, previous_message_id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_message_metadata(existing_metadata, thinking) do
    existing_metadata
    |> carry_forward_metadata()
    |> put_metadata_value("thinking", blank_to_nil(thinking))
  end

  defp put_metadata_value(metadata, key, nil), do: Map.delete(metadata, key)
  defp put_metadata_value(metadata, key, value), do: Map.put(metadata, key, value)

  defp normalize_metadata_map(nil), do: %{}
  defp normalize_metadata_map(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata_map(_metadata), do: %{}

  defp merge_tool_response(tool_responses, tool_response) do
    case Map.get(tool_response, "id") do
      nil ->
        tool_responses ++ [tool_response]

      tool_response_id ->
        case Enum.find_index(tool_responses, &(Map.get(&1, "id") == tool_response_id)) do
          nil ->
            tool_responses ++ [tool_response]

          index ->
            List.replace_at(
              tool_responses,
              index,
              Map.merge(Enum.at(tool_responses, index), tool_response)
            )
        end
    end
  end

  defp persist_tool_message(state, tool_result) do
    parent_message_id = tool_parent_message_id(state)

    case {Map.get(tool_result, "id"), Map.get(tool_result, "name")} do
      {tool_call_id, tool_name}
      when is_binary(tool_call_id) and tool_call_id != "" and is_binary(tool_name) and
             tool_name != "" ->
        attrs = tool_message_attrs(parent_message_id, tool_result, state.next_tool_position)

        case Chat.get_tool_message(parent_message_id, tool_call_id) do
          nil ->
            case Chat.create_message(state.chat_room, attrs) do
              {:ok, tool_message} ->
                {:ok, %{state | next_tool_position: tool_message.position + 1}, tool_message}

              {:error, _reason} = error ->
                error
            end

          tool_message ->
            case Chat.update_message(
                   tool_message,
                   Map.drop(attrs, [:role, :parent_message_id, :position])
                 ) do
              {:ok, updated_tool_message} -> {:ok, state, updated_tool_message}
              {:error, _reason} = error -> error
            end
        end

      _other ->
        {:error, :invalid_tool_result}
    end
  end

  defp tool_message_attrs(parent_message_id, tool_result, position) do
    %{
      role: "tool",
      content: blank_to_nil(Map.get(tool_result, "content")),
      name: Map.get(tool_result, "name"),
      tool_call_id: Map.get(tool_result, "id"),
      position: position,
      status: tool_message_status(tool_result),
      metadata: tool_message_metadata(tool_result),
      parent_message_id: parent_message_id
    }
  end

  defp tool_message_status(%{"status" => "error"}), do: :error
  defp tool_message_status(%{"status" => "running"}), do: :pending
  defp tool_message_status(_tool_result), do: :completed

  defp tool_message_metadata(tool_result) do
    %{}
    |> put_metadata_value("arguments", Map.get(tool_result, "arguments"))
    |> put_metadata_value("tool_status", Map.get(tool_result, "status"))
  end

  defp tool_parent_message_id(%{tool_parent_message_id: nil, message_id: message_id}),
    do: message_id

  defp tool_parent_message_id(%{tool_parent_message_id: tool_parent_message_id}),
    do: tool_parent_message_id

  defp tool_call_message_metadata(existing_metadata, thinking, tool_call_turn) do
    existing_metadata
    |> carry_forward_metadata()
    |> put_metadata_value("thinking", blank_to_nil(thinking))
    |> put_metadata_value("tool_calls", empty_to_nil(turn_tool_calls(tool_call_turn)))
  end

  defp carry_forward_metadata(existing_metadata) do
    existing_metadata
    |> normalize_metadata_map()
    |> Map.drop([
      "usage",
      "thinking",
      "tool_calls",
      "tool_call_turns",
      "tool_responses",
      "finish_reason",
      "provider_meta",
      "error",
      "cancelled"
    ])
  end

  defp turn_content(%{} = tool_call_turn) do
    Map.get(tool_call_turn, "content") || Map.get(tool_call_turn, :content)
  end

  defp turn_tool_calls(%{} = tool_call_turn) do
    tool_call_turn
    |> Map.get("tool_calls", Map.get(tool_call_turn, :tool_calls, []))
    |> List.wrap()
  end

  defp tool_call_id(%{} = tool_call), do: Map.get(tool_call, "id") || Map.get(tool_call, :id)
  defp tool_call_id(_tool_call), do: nil

  defp tool_turn_complete?(%{pending_tool_call_ids: []} = state) do
    Enum.any?(state.tool_responses, fn tool_response ->
      Map.get(tool_response, "status") != "running"
    end)
  end

  defp tool_turn_complete?(state) do
    Enum.all?(state.pending_tool_call_ids, fn pending_tool_call_id ->
      case Enum.find(state.tool_responses, &(Map.get(&1, "id") == pending_tool_call_id)) do
        nil -> false
        tool_response -> Map.get(tool_response, "status") != "running"
      end
    end)
  end

  defp completed_turn_position(%{next_tool_position: nil}, current_position), do: current_position

  defp completed_turn_position(%{next_tool_position: next_tool_position}, _current_position),
    do: next_tool_position

  defp reserved_message_position(completed_position), do: completed_position + 1000

  defp final_message_position(%{next_tool_position: nil}), do: nil
  defp final_message_position(%{next_tool_position: next_tool_position}), do: next_tool_position

  defp maybe_put_position(attrs, nil), do: attrs
  defp maybe_put_position(attrs, position), do: Map.put(attrs, :position, position)

  defp stream_placeholder_status(content) when content in [nil, ""], do: :pending
  defp stream_placeholder_status(_content), do: :streaming

  defp append_text(current, token), do: (current || "") <> token

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp error_message({:error, reason}), do: error_message(reason)
  defp error_message({reason, _stacktrace}), do: error_message(reason)
  defp error_message(%{reason: reason}) when not is_nil(reason), do: error_message(reason)
  defp error_message(%{"reason" => reason}) when not is_nil(reason), do: error_message(reason)

  defp error_message(%{response_body: %{"message" => message}}) when is_binary(message),
    do: message

  defp error_message(%{"response_body" => %{"message" => message}}) when is_binary(message),
    do: message

  defp error_message(%{message: message}) when is_binary(message), do: message
  defp error_message(%{"message" => message}) when is_binary(message), do: message
  defp error_message(%{__exception__: true} = exception), do: Exception.message(exception)
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason) when is_atom(reason), do: Phoenix.Naming.humanize(to_string(reason))
  defp error_message(_reason), do: "Unexpected error"
end
