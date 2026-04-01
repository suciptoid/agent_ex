defmodule App.Chat.StreamWorker do
  @moduledoc """
  Runs chat message streaming outside of the LiveView lifecycle.
  """

  use GenServer

  require Logger

  alias App.Chat
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
      content: Keyword.get(opts, :content, "") || "",
      thinking: Keyword.get(opts, :thinking, "") || "",
      tool_responses: Keyword.get(opts, :tool_responses, []),
      metadata: Keyword.get(opts, :metadata, %{}) || %{},
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
          on_tool_start: fn tool_result ->
            send(worker_pid, {:stream_tool_started, tool_result})
          end,
          on_tool_result: fn tool_result ->
            send(worker_pid, {:stream_tool_result, tool_result})
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

        case Orchestrator.stream_message(state.chat_room, state.messages, callbacks) do
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
    _ = Task.shutdown(state.task, :brutal_kill)

    persisted? =
      persist_cancel(
        state.chat_room,
        state.message_id,
        state.content,
        state.metadata,
        state.thinking,
        state.tool_responses
      )

    if persisted? do
      broadcast_message_update(state.chat_room.id, state.message_id)
    end

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:stream_chunk, token}, state) do
    new_content = append_text(state.content, token)
    new_count = state.token_count + 1

    state = %{state | content: new_content, token_count: new_count}
    broadcast(state.chat_room.id, {:stream_chunk, state.message_id, token})

    if rem(new_count, @stream_db_write_every) == 0 do
      maybe_update_streaming_message(
        state.message_id,
        new_content,
        stream_placeholder_status(new_content),
        build_message_metadata(state.metadata, state.thinking, state.tool_responses)
      )
    end

    {:noreply, state}
  end

  def handle_info({:stream_thinking_chunk, token}, state) do
    state = %{state | thinking: append_text(state.thinking, token)}
    broadcast(state.chat_room.id, {:stream_thinking_chunk, state.message_id, token})
    {:noreply, state}
  end

  def handle_info({:stream_tool_started, tool_result}, state) do
    tool_responses = merge_tool_response(state.tool_responses, tool_result)
    state = %{state | tool_responses: tool_responses}

    maybe_update_streaming_message(
      state.message_id,
      state.content,
      stream_placeholder_status(state.content),
      build_message_metadata(state.metadata, state.thinking, tool_responses)
    )

    broadcast(state.chat_room.id, {:stream_tool_started, state.message_id, tool_result})
    {:noreply, state}
  end

  def handle_info({:stream_tool_result, tool_result}, state) do
    tool_responses = merge_tool_response(state.tool_responses, tool_result)
    state = %{state | tool_responses: tool_responses}

    maybe_update_streaming_message(
      state.message_id,
      state.content,
      stream_placeholder_status(state.content),
      build_message_metadata(state.metadata, state.thinking, tool_responses)
    )

    broadcast(state.chat_room.id, {:stream_tool_result, state.message_id, tool_result})
    {:noreply, state}
  end

  def handle_info({ref, {:stream_done, result}}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, %{content: content, agent_id: agent_id, metadata: metadata}} ->
        persist_success(state.chat_room, state.message_id, content, agent_id, metadata)

      {:error, reason} ->
        error_text = error_message(reason)
        persist_error(state.chat_room, state.message_id, error_text, state)
    end

    broadcast_message_update(state.chat_room.id, state.message_id)
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    Logger.error(
      "[StreamWorker] Streaming task crashed for message #{state.message_id}: #{inspect(reason)}"
    )

    persist_error(state.chat_room, state.message_id, "The agent encountered an error", state)
    broadcast_message_update(state.chat_room.id, state.message_id)
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp persist_success(chat_room, message_id, content, agent_id, metadata) do
    attrs = %{
      content: content,
      agent_id: agent_id,
      metadata: metadata,
      status: :completed
    }

    persist_message(chat_room, message_id, attrs)
  end

  defp persist_error(chat_room, message_id, error_text, state) do
    metadata =
      build_message_metadata(state.metadata, state.thinking, state.tool_responses)
      |> Map.put("error", error_text)

    persist_message(chat_room, message_id, %{
      content: error_text,
      status: :error,
      metadata: metadata
    })
  end

  defp persist_cancel(chat_room, message_id, content, metadata, thinking, tool_responses) do
    cancel_text = "Response cancelled."

    persist_message(chat_room, message_id, %{
      content: blank_to_nil(content) || cancel_text,
      status: :error,
      metadata:
        build_message_metadata(metadata, thinking, tool_responses)
        |> Map.put("error", cancel_text)
        |> Map.put("cancelled", true)
    })
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
    Phoenix.PubSub.broadcast(App.PubSub, Chat.chat_room_topic(chat_room_id), message)
  end

  defp build_message_metadata(existing_metadata, thinking, tool_responses) do
    existing_metadata
    |> normalize_metadata_map()
    |> put_metadata_value("thinking", blank_to_nil(thinking))
    |> put_metadata_value("tool_responses", empty_to_nil(tool_responses))
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

  defp stream_placeholder_status(content) when content in [nil, ""], do: :pending
  defp stream_placeholder_status(_content), do: :streaming

  defp append_text(current, token), do: (current || "") <> token

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp error_message(%{message: message}) when is_binary(message), do: message
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason) when is_atom(reason), do: Phoenix.Naming.humanize(to_string(reason))
  defp error_message(reason), do: inspect(reason)
end
