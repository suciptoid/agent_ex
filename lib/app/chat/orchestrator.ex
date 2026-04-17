defmodule App.Chat.Orchestrator do
  @moduledoc """
  Handles message orchestration for chat rooms.
  """

  require Logger

  alias App.Chat
  alias App.Chat.{ChatRoom, ChatRoomAgent, ContextBuilder, Message}

  def send_message(_scope, %ChatRoom{} = chat_room, content) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      {:error, "Message cannot be blank"}
    else
      Logger.info(
        "[Orchestrator] Sending message to room #{chat_room.id}, content length: #{String.length(content)}"
      )

      with {:ok, _user_message} <-
             Chat.create_message(chat_room, %{role: "user", content: content}),
           messages <- Chat.list_messages(chat_room),
           {:ok, agent} <- active_agent(chat_room) do
        Logger.debug("[Orchestrator] Running agent #{agent.name} (#{agent.id})")

        callbacks = [recipient: nil]

        run_opts =
          chat_room
          |> multi_agent_opts(messages, callbacks)
          |> maybe_inject_title_tool(chat_room, callbacks)

        maybe_seed_initial_title(chat_room, messages, callbacks)

        case run_sync_with_context_control(chat_room, agent, messages, run_opts) do
          {:ok, result} ->
            assistant_content = result.content || "The agent returned an empty response."

            Logger.info(
              "[Orchestrator] Got response, length: #{String.length(assistant_content)}"
            )

            persist_agent_result(chat_room, agent.id, result)

          {:error, reason} ->
            Logger.error("[Orchestrator] Agent run failed: #{delegated_error_text(reason)}")
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Streams a response from the active agent for the given messages.

  The third argument may be a pid or a keyword list of callbacks.
  """
  def stream_message(%ChatRoom{} = chat_room, messages, recipient_or_callbacks) do
    with {:ok, agent} <- active_agent(chat_room) do
      Logger.debug("[Orchestrator] Streaming agent #{agent.name} (#{agent.id})")
      callbacks = normalize_stream_callbacks(recipient_or_callbacks)

      run_opts =
        chat_room
        |> multi_agent_opts(messages, callbacks)
        |> Keyword.merge(forwarded_stream_run_opts(callbacks))
        |> Keyword.merge(callback_run_opts(callbacks))
        |> maybe_inject_title_tool(chat_room, callbacks)

      maybe_seed_initial_title(chat_room, messages, callbacks)

      case run_streaming_with_context_control(
             chat_room,
             agent,
             messages,
             callbacks[:recipient],
             run_opts
           ) do
        {:ok, result} ->
          {:ok,
           %{
             content: result.content,
             agent_id: agent.id,
             metadata: response_metadata(result),
             tool_responses: Map.get(result, :tool_responses, []),
             tool_call_turns: Map.get(result, :tool_call_turns, [])
           }}

        {:error, reason} ->
          Logger.error("[Orchestrator] Streaming failed: #{delegated_error_text(reason)}")
          {:error, reason}
      end
    end
  end

  defp active_agent(%ChatRoom{chat_room_agents: chat_room_agents}) do
    case Enum.find(chat_room_agents, & &1.is_active) || List.first(chat_room_agents) do
      %ChatRoomAgent{agent: agent} -> {:ok, agent}
      nil -> {:error, "This chat room has no agents assigned"}
    end
  end

  # Returns extra opts for multi-agent rooms: system prompt roster + handover/ask_agent tools
  defp multi_agent_opts(
         %ChatRoom{chat_room_agents: chat_room_agents} = chat_room,
         messages,
         callbacks
       ) do
    agents = Enum.map(chat_room_agents, & &1.agent)

    if length(agents) <= 1 do
      []
    else
      agent_roster =
        agents
        |> Enum.map(fn a ->
          desc =
            if blank?(a.system_prompt),
              do: "general assistant",
              else: String.slice(a.system_prompt, 0, 120)

          "- #{a.name} (id: #{a.id}): #{desc}"
        end)
        |> Enum.join("\n")

      extra_prompt = """
      ## Multi-Agent Room
      You are the active agent. Other agents available in this room:
      #{agent_roster}

      You have two special tools available:
      - `handover`: Transfer control to another agent, making them the active agent for future messages.
      - `ask_agent`: Delegate a task to another agent and receive their response in this conversation. The delegated agent will post their reply as a message in the chat.
      """

      agent_map = Map.new(agents, fn a -> {to_string(a.id), a} end)

      alloy_context = %{
        chat_room: chat_room,
        agent_map: agent_map,
        callbacks: callbacks,
        messages_snapshot: messages,
        run_delegated_agent: &run_delegated_agent/6
      }

      [
        extra_system_prompt: extra_prompt,
        extra_tools: [
          App.Agents.AlloyTools.Handover,
          App.Agents.AlloyTools.AskAgent
        ],
        alloy_context: alloy_context
      ]
    end
  end

  defp run_delegated_agent(
         %ChatRoom{} = chat_room,
         target_agent,
         messages_snapshot,
         instructions,
         placeholder_message,
         callbacks
       ) do
    sub_messages = messages_snapshot ++ [%{role: "user", content: instructions}]

    stream_opts = [
      on_result: fn token ->
        notify_agent_message_stream_chunk(callbacks, placeholder_message.id, token)
      end,
      on_thinking: fn token ->
        notify_agent_message_thinking_chunk(callbacks, placeholder_message.id, token)
      end,
      on_tool_start: fn tool_result ->
        notify_agent_message_tool_started(callbacks, placeholder_message.id, tool_result)
      end,
      on_tool_result: fn tool_result ->
        notify_agent_message_tool_result(callbacks, placeholder_message.id, tool_result)
      end
    ]

    case run_streaming_with_context_control(
           chat_room,
           target_agent,
           sub_messages,
           nil,
           stream_opts
         ) do
      {:ok, result} ->
        metadata =
          delegated_message_metadata(
            placeholder_message.metadata,
            response_metadata: response_metadata(result)
          )

        persist_delegated_message(
          chat_room,
          placeholder_message,
          %{
            content: result.content,
            status: :completed,
            metadata: metadata,
            agent_id: target_agent.id
          },
          Map.get(result, :tool_responses, []),
          callbacks
        )

      {:error, reason} ->
        Logger.error(
          "[Orchestrator] Delegated agent #{target_agent.name} failed: #{delegated_error_text(reason)}"
        )

        error_text = delegated_error_text(reason)

        metadata =
          delegated_message_metadata(placeholder_message.metadata,
            error: error_text
          )

        persist_delegated_message(
          chat_room,
          placeholder_message,
          %{
            content: error_text,
            status: :error,
            metadata: metadata,
            agent_id: target_agent.id
          },
          [],
          callbacks
        )
    end
  end

  defp persist_delegated_message(chat_room, placeholder_message, attrs, tool_responses, callbacks) do
    case Chat.get_message_by_id(placeholder_message.id) do
      nil ->
        case Chat.create_message(chat_room, Map.put_new(attrs, :role, "assistant")) do
          {:ok, message} ->
            case persist_tool_messages(chat_room, message, tool_responses) do
              {:ok, reloaded_message} ->
                notify_agent_message_created(callbacks, reloaded_message)

              {:error, reason} ->
                Logger.error(
                  "[Orchestrator] Failed to persist delegated tool messages #{placeholder_message.id}: #{inspect(reason)}"
                )
            end

          {:error, reason} ->
            Logger.error(
              "[Orchestrator] Failed to persist delegated message #{placeholder_message.id}: #{inspect(reason)}"
            )
        end

      existing_message ->
        case Chat.update_message(existing_message, attrs) do
          {:ok, message} ->
            case persist_tool_messages(chat_room, message, tool_responses) do
              {:ok, reloaded_message} ->
                notify_agent_message_updated(callbacks, reloaded_message)

              {:error, reason} ->
                Logger.error(
                  "[Orchestrator] Failed to persist delegated tool messages #{placeholder_message.id}: #{inspect(reason)}"
                )
            end

          {:error, reason} ->
            Logger.error(
              "[Orchestrator] Failed to update delegated message #{placeholder_message.id}: #{inspect(reason)}"
            )
        end
    end
  end

  defp delegated_message_metadata(existing_metadata, extra_attrs) do
    existing_metadata
    |> normalize_metadata()
    |> Kernel.||(%{})
    |> Map.merge(%{"delegated" => true, "tool_name" => "ask_agent"})
    |> Map.merge(Keyword.get(extra_attrs, :response_metadata, %{}))
    |> maybe_put_metadata("error", Keyword.get(extra_attrs, :error))
  end

  defp maybe_put_metadata(metadata, _key, nil), do: metadata
  defp maybe_put_metadata(metadata, key, value), do: Map.put(metadata, key, value)

  defp delegated_error_text({:error, reason}), do: delegated_error_text(reason)
  defp delegated_error_text({reason, _stacktrace}), do: delegated_error_text(reason)

  defp delegated_error_text(%{reason: reason}) when not is_nil(reason),
    do: delegated_error_text(reason)

  defp delegated_error_text(%{"reason" => reason}) when not is_nil(reason),
    do: delegated_error_text(reason)

  defp delegated_error_text(%{response_body: %{"message" => message}}) when is_binary(message),
    do: message

  defp delegated_error_text(%{"response_body" => %{"message" => message}})
       when is_binary(message),
       do: message

  defp delegated_error_text(%{message: message}) when is_binary(message), do: message
  defp delegated_error_text(%{"message" => message}) when is_binary(message), do: message
  defp delegated_error_text(%{__exception__: true} = exception), do: Exception.message(exception)
  defp delegated_error_text(reason) when is_binary(reason), do: reason

  defp delegated_error_text(reason) when is_atom(reason),
    do: Phoenix.Naming.humanize(to_string(reason))

  defp delegated_error_text(_reason), do: "Unexpected error"

  defp response_metadata(result) do
    %{}
    |> maybe_put_metadata("usage", Map.get(result, :usage))
    |> maybe_put_metadata("thinking", blank_to_nil(Map.get(result, :thinking)))
    |> maybe_put_metadata("finish_reason", Map.get(result, :finish_reason))
    |> maybe_put_metadata("provider_meta", normalize_metadata(Map.get(result, :provider_meta)))
    |> maybe_put_metadata("provider_state", normalize_metadata(Map.get(result, :provider_state)))
  end

  defp normalize_metadata(nil), do: nil
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp empty_list_to_nil([]), do: nil
  defp empty_list_to_nil(value), do: value

  defp tool_call_turns(result) do
    case Map.get(result, :tool_call_turns, []) do
      [] -> tool_call_turns_from_tool_responses(Map.get(result, :tool_responses, []))
      tool_call_turns -> tool_call_turns
    end
  end

  defp tool_call_turns_from_tool_responses([]), do: []

  defp tool_call_turns_from_tool_responses(tool_responses) do
    [
      %{
        "tool_calls" =>
          Enum.map(tool_responses, fn tool_response ->
            %{}
            |> maybe_put_metadata("id", Map.get(tool_response, "id"))
            |> maybe_put_metadata("name", Map.get(tool_response, "name"))
            |> maybe_put_metadata(
              "arguments",
              normalize_metadata(Map.get(tool_response, "arguments"))
            )
          end)
      }
    ]
  end

  defp turn_content(%{} = tool_call_turn) do
    Map.get(tool_call_turn, "content") || Map.get(tool_call_turn, :content)
  end

  defp turn_thinking(%{} = tool_call_turn) do
    Map.get(tool_call_turn, "thinking") || Map.get(tool_call_turn, :thinking)
  end

  defp turn_tool_calls(%{} = tool_call_turn) do
    tool_call_turn
    |> Map.get("tool_calls", Map.get(tool_call_turn, :tool_calls, []))
    |> List.wrap()
  end

  defp tool_call_id(%{} = tool_call), do: Map.get(tool_call, "id") || Map.get(tool_call, :id)
  defp tool_call_id(_tool_call), do: nil

  defp blank?(value), do: value in [nil, ""]

  defp run_sync_with_context_control(%ChatRoom{} = chat_room, agent, messages, run_opts) do
    run_with_context_control(chat_room, agent, messages, run_opts, fn prepared_messages ->
      agent_runner().run(agent, prepared_messages, run_opts)
    end)
  end

  defp run_streaming_with_context_control(
         %ChatRoom{} = chat_room,
         agent,
         messages,
         recipient,
         run_opts
       ) do
    run_with_context_control(chat_room, agent, messages, run_opts, fn prepared_messages ->
      agent_runner().run_streaming(agent, prepared_messages, recipient, run_opts)
    end)
  end

  defp run_with_context_control(%ChatRoom{} = chat_room, agent, messages, run_opts, runner_fun) do
    with {:ok, prepared_messages} <-
           prepare_context_messages(chat_room, agent, messages, run_opts, force_compaction: false),
         result <- runner_fun.(prepared_messages) do
      case result do
        {:error, reason} ->
          if context_window_error?(reason) do
            retry_with_forced_compaction(chat_room, agent, messages, run_opts, runner_fun, reason)
          else
            {:error, reason}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_forced_compaction(
         %ChatRoom{} = chat_room,
         agent,
         messages,
         run_opts,
         runner_fun,
         initial_reason
       ) do
    Logger.warning(
      "[Orchestrator] Context window overflow detected for room #{chat_room.id}; retrying with forced compaction: #{inspect(initial_reason)}"
    )

    :telemetry.execute(
      [:app, :chat, :context, :overflow_retry],
      %{count: 1},
      %{
        chat_room_id: chat_room.id,
        agent_id: agent_id(agent),
        reason: inspect(initial_reason)
      }
    )

    budget_overrides = overflow_budget_overrides(initial_reason)

    with {:ok, prepared_messages} <-
           prepare_context_messages(chat_room, agent, messages, run_opts,
             force_compaction: true,
             budget_overrides: budget_overrides
           ),
         result <- runner_fun.(prepared_messages) do
      case result do
        {:error, reason} ->
          if context_window_error?(reason) do
            if not checkpoint_message_present?(prepared_messages) do
              ensure_overflow_checkpoint(chat_room, agent, messages, run_opts, budget_overrides)
            end

            {:error, overflow_retry_error()}
          else
            {:error, reason}
          end

        other ->
          other
      end
    else
      {:error, reason} ->
        Logger.error(
          "[Orchestrator] Failed to prepare forced-compaction context: #{inspect(reason)}"
        )

        ensure_overflow_checkpoint(chat_room, agent, messages, run_opts, budget_overrides)
        {:error, overflow_retry_error()}
    end
  end

  defp prepare_context_messages(%ChatRoom{} = chat_room, agent, messages, run_opts, opts) do
    extra_system_prompt = Keyword.get(run_opts, :extra_system_prompt, "")
    force_compaction? = Keyword.get(opts, :force_compaction, false)
    budget_overrides = Keyword.get(opts, :budget_overrides, %{})

    {:ok, %{messages: prepared_messages, estimated_tokens: estimated_tokens}} =
      ContextBuilder.prepare(chat_room, agent, messages,
        extra_system_prompt: extra_system_prompt,
        force_compaction: force_compaction?,
        budget_overrides: budget_overrides
      )

    Logger.debug(
      "[Orchestrator] Prepared #{length(prepared_messages)} prompt messages for #{chat_room.id} (~#{estimated_tokens} tokens)"
    )

    :telemetry.execute(
      [:app, :chat, :context, :prepared],
      %{
        estimated_tokens: estimated_tokens,
        message_count: length(prepared_messages),
        checkpoint_count: Enum.count(prepared_messages, &(&1.role == "checkpoint"))
      },
      %{
        chat_room_id: chat_room.id,
        agent_id: agent_id(agent),
        force_compaction: force_compaction?
      }
    )

    {:ok, prepared_messages}
  end

  defp context_window_error?(%{reason: reason}), do: context_window_error?(reason)
  defp context_window_error?(%{message: message}), do: context_window_error?(message)

  defp context_window_error?(reason) when is_binary(reason) do
    normalized = String.downcase(reason)

    Enum.any?(
      [
        "maximum context length",
        "context length",
        "context window",
        "input is too long",
        "prompt is too long"
      ],
      &String.contains?(normalized, &1)
    )
  end

  defp context_window_error?(reason), do: reason |> inspect() |> context_window_error?()

  defp agent_id(%{id: agent_id}), do: agent_id
  defp agent_id(_agent), do: nil

  defp checkpoint_message_present?(messages) when is_list(messages) do
    Enum.any?(messages, &((Map.get(&1, :role) || Map.get(&1, "role")) == "checkpoint"))
  end

  defp checkpoint_message_present?(_messages), do: false

  defp overflow_budget_overrides(reason) do
    case parse_context_window_limit(reason) do
      nil -> %{}
      context_window_tokens -> %{context_window_tokens: context_window_tokens}
    end
  end

  defp parse_context_window_limit(%{reason: reason}), do: parse_context_window_limit(reason)
  defp parse_context_window_limit(%{message: message}), do: parse_context_window_limit(message)

  defp parse_context_window_limit(reason) when is_binary(reason) do
    case Regex.run(~r/maximum context length is (\d+)/i, reason, capture: :all_but_first) do
      [token_limit] ->
        case Integer.parse(token_limit) do
          {context_window_tokens, _rest} -> context_window_tokens
          :error -> nil
        end

      _other ->
        nil
    end
  end

  defp parse_context_window_limit(_reason), do: nil

  defp ensure_overflow_checkpoint(
         %ChatRoom{} = chat_room,
         agent,
         messages,
         run_opts,
         budget_overrides
       ) do
    extra_system_prompt = Keyword.get(run_opts, :extra_system_prompt, "")

    aggressive_overrides =
      budget_overrides
      |> Map.new()
      |> Map.merge(%{
        raw_tail_tokens: 0,
        force_raw_tail_tokens: 0,
        checkpoint_source_tokens: 8_000,
        force_checkpoint_source_tokens: 8_000
      })

    {:ok, _prepared} =
      ContextBuilder.prepare(chat_room, agent, messages,
        extra_system_prompt: extra_system_prompt,
        force_compaction: true,
        budget_overrides: aggressive_overrides
      )

    :ok
  end

  defp overflow_retry_error do
    "Conversation exceeded the model context window even after compacting older history. Start a new chat or trim earlier tool-heavy turns."
  end

  defp normalize_stream_callbacks(recipient) when is_pid(recipient) do
    [
      recipient: recipient,
      on_result: nil,
      on_thinking: nil,
      on_tool_calls: nil,
      on_tool_start: nil,
      on_tool_result: nil
    ]
  end

  defp normalize_stream_callbacks(callbacks) when is_list(callbacks) do
    Keyword.put_new(callbacks, :recipient, nil)
  end

  defp normalize_stream_callbacks(_other), do: [recipient: nil]

  defp callback_run_opts(callbacks) do
    [
      on_result: callbacks[:on_result],
      on_thinking: callbacks[:on_thinking],
      on_tool_calls: callbacks[:on_tool_calls],
      on_tool_start: callbacks[:on_tool_start],
      on_tool_result: callbacks[:on_tool_result]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp forwarded_stream_run_opts(callbacks) do
    Keyword.drop(callbacks, [
      :recipient,
      :on_result,
      :on_thinking,
      :on_tool_calls,
      :on_tool_start,
      :on_tool_result,
      :on_title_updated,
      :on_agent_message_created,
      :on_agent_message_stream_chunk,
      :on_agent_message_thinking_chunk,
      :on_agent_message_tool_started,
      :on_agent_message_tool_result,
      :on_agent_message_updated,
      :on_active_agent_changed
    ])
  end

  defp persist_tool_messages(_chat_room, %Message{} = message, []),
    do: {:ok, Chat.get_message_by_id(message.id) || message}

  defp persist_tool_messages(%ChatRoom{} = chat_room, %Message{} = message, tool_responses) do
    Enum.reduce_while(tool_responses, :ok, fn tool_response, :ok ->
      case Chat.create_message(chat_room, tool_message_attrs(message, tool_response)) do
        {:ok, _tool_message} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> {:ok, Chat.get_message_by_id(message.id) || message}
      {:error, _reason} = error -> error
    end
  end

  defp tool_message_attrs(%Message{id: parent_message_id}, tool_response) do
    %{
      role: "tool",
      content: blank_to_nil(Map.get(tool_response, "content")),
      name: Map.get(tool_response, "name"),
      tool_call_id: Map.get(tool_response, "id"),
      status: tool_message_status(tool_response),
      metadata: tool_message_metadata(tool_response),
      parent_message_id: parent_message_id
    }
  end

  defp tool_message_status(%{"status" => "error"}), do: :error
  defp tool_message_status(%{"status" => "running"}), do: :pending
  defp tool_message_status(_tool_response), do: :completed

  defp tool_message_metadata(tool_response) do
    %{}
    |> maybe_put_metadata("arguments", normalize_metadata(Map.get(tool_response, "arguments")))
    |> maybe_put_metadata("tool_status", Map.get(tool_response, "status"))
  end

  defp persist_agent_result(%ChatRoom{} = chat_room, agent_id, result) do
    case tool_call_turns(result) do
      [] ->
        Chat.create_message(chat_room, %{
          role: "assistant",
          content: normalized_final_content(result),
          agent_id: agent_id,
          metadata: response_metadata(result)
        })

      tool_call_turns ->
        with {:ok, _remaining_tool_responses} <-
               persist_tool_call_turns(
                 chat_room,
                 agent_id,
                 tool_call_turns,
                 Map.get(result, :tool_responses, [])
               ) do
          Chat.create_message(chat_room, %{
            role: "assistant",
            content: normalized_final_content(result),
            agent_id: agent_id,
            metadata: response_metadata(result)
          })
        end
    end
  end

  defp persist_tool_call_turns(chat_room, agent_id, tool_call_turns, tool_responses) do
    Enum.reduce_while(tool_call_turns, {:ok, tool_responses}, fn tool_call_turn,
                                                                 {:ok, remaining_tool_responses} ->
      with {:ok, assistant_message} <-
             Chat.create_message(chat_room, %{
               role: "assistant",
               content: blank_to_nil(turn_content(tool_call_turn)),
               agent_id: agent_id,
               metadata: tool_call_message_metadata(tool_call_turn)
             }),
           {:ok, next_remaining_tool_responses} <-
             persist_tool_messages_for_turn(
               chat_room,
               assistant_message,
               remaining_tool_responses,
               turn_tool_calls(tool_call_turn)
             ) do
        {:cont, {:ok, next_remaining_tool_responses}}
      else
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_tool_messages_for_turn(chat_room, assistant_message, tool_responses, tool_calls) do
    {selected_tool_responses, remaining_tool_responses} =
      split_tool_responses_for_turn(tool_responses, tool_calls)

    case persist_tool_messages(chat_room, assistant_message, selected_tool_responses) do
      {:ok, _assistant_message} -> {:ok, remaining_tool_responses}
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_tool_responses_for_turn(tool_responses, tool_calls) do
    case tool_calls |> Enum.map(&tool_call_id/1) |> Enum.reject(&blank?/1) do
      [] ->
        {tool_responses, []}

      tool_call_ids ->
        selected_tool_responses =
          tool_call_ids
          |> Enum.map(fn tool_call_id ->
            Enum.find(tool_responses, &(Map.get(&1, "id") == tool_call_id))
          end)
          |> Enum.reject(&is_nil/1)

        remaining_tool_responses =
          Enum.reject(tool_responses, &(Map.get(&1, "id") in tool_call_ids))

        {selected_tool_responses, remaining_tool_responses}
    end
  end

  defp tool_call_message_metadata(tool_call_turn) do
    %{}
    |> maybe_put_metadata("thinking", blank_to_nil(turn_thinking(tool_call_turn)))
    |> maybe_put_metadata("tool_calls", empty_list_to_nil(turn_tool_calls(tool_call_turn)))
  end

  defp normalized_final_content(result) do
    case blank_to_nil(Map.get(result, :content)) do
      nil -> "The agent returned an empty response."
      content -> content
    end
  end

  defp notify_agent_message_created(callbacks, message) do
    call_callback(
      callbacks[:on_agent_message_created],
      [message],
      fn recipient ->
        send(recipient, {:agent_message_created, message})
      end,
      callbacks[:recipient]
    )
  end

  defp notify_agent_message_stream_chunk(callbacks, message_id, token) do
    call_callback(
      callbacks[:on_agent_message_stream_chunk],
      [message_id, token],
      fn recipient ->
        send(recipient, {:agent_message_stream_chunk, message_id, token})
      end,
      callbacks[:recipient]
    )
  end

  defp notify_agent_message_thinking_chunk(callbacks, message_id, token) do
    call_callback(
      callbacks[:on_agent_message_thinking_chunk],
      [message_id, token],
      fn recipient ->
        send(recipient, {:agent_message_thinking_chunk, message_id, token})
      end,
      callbacks[:recipient]
    )
  end

  defp notify_agent_message_tool_started(callbacks, message_id, tool_result) do
    call_callback(
      callbacks[:on_agent_message_tool_started],
      [message_id, tool_result],
      fn recipient ->
        send(recipient, {:agent_message_tool_started, message_id, tool_result})
      end,
      callbacks[:recipient]
    )
  end

  defp notify_agent_message_tool_result(callbacks, message_id, tool_result) do
    call_callback(
      callbacks[:on_agent_message_tool_result],
      [message_id, tool_result],
      fn recipient ->
        send(recipient, {:agent_message_tool_result, message_id, tool_result})
      end,
      callbacks[:recipient]
    )
  end

  defp notify_agent_message_updated(callbacks, message) do
    call_callback(
      callbacks[:on_agent_message_updated],
      [message],
      fn recipient ->
        send(recipient, {:agent_message_updated, message})
      end,
      callbacks[:recipient]
    )
  end

  defp call_callback(callback, args, _fallback, _recipient) when is_function(callback) do
    apply_callback(callback, args)
  end

  defp call_callback(_callback, _args, fallback, recipient) when is_pid(recipient) do
    fallback.(recipient)
  end

  defp call_callback(_callback, _args, _fallback, _recipient), do: :ok

  defp apply_callback(callback, [arg]) when is_function(callback, 1), do: callback.(arg)

  defp apply_callback(callback, [arg1, arg2]) when is_function(callback, 2),
    do: callback.(arg1, arg2)

  defp apply_callback(_callback, _args), do: :ok

  defp maybe_inject_title_tool(opts, %ChatRoom{title: title} = chat_room, callbacks)
       when title in [nil, ""] do
    extra_tools =
      (Keyword.get(opts, :extra_tools, []) ++ [App.Agents.AlloyTools.UpdateTitle])
      |> Enum.uniq()

    title_context = %{
      chat_room: chat_room,
      callbacks: callbacks
    }

    existing_context = Keyword.get(opts, :alloy_context, %{})

    extra_prompt =
      (Keyword.get(opts, :extra_system_prompt, "") <>
         """

         ## Auto-Title
         This is a new conversation without a title. Before your final response,
         call the `update_chatroom_title` tool with a concise title (under 60 chars)
         that summarizes what the user is asking about. If you are already calling
         other tools, include `update_chatroom_title` in the same tool-call batch
         instead of creating a separate tool-only turn. Do not mention this action
         in your response to the user.
         """)
      |> String.trim()

    opts
    |> Keyword.put(:extra_tools, extra_tools)
    |> Keyword.put(:extra_system_prompt, extra_prompt)
    |> Keyword.put(:alloy_context, Map.merge(existing_context, title_context))
  end

  defp maybe_inject_title_tool(opts, _chat_room, _callbacks), do: opts

  defp maybe_seed_initial_title(%ChatRoom{title: title} = chat_room, messages, callbacks)
       when title in [nil, ""] do
    case fallback_title_from_messages(messages) do
      nil -> :ok
      generated_title -> persist_title_update(chat_room, callbacks, generated_title)
    end
  end

  defp maybe_seed_initial_title(_chat_room, _messages, _callbacks), do: :ok

  defp fallback_title_from_messages(messages) do
    messages
    |> Enum.find_value(fn
      %{role: "user", content: content} when is_binary(content) ->
        normalize_generated_title(content)

      _ ->
        nil
    end)
  end

  defp normalize_generated_title(content) do
    content
    |> String.split(~r/\R+/, trim: true)
    |> List.first()
    |> case do
      nil ->
        nil

      first_line ->
        first_line
        |> String.replace(~r/^\s*[#>*-]+\s*/, "")
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
        |> String.replace(~r/[[:punct:]\s]+$/u, "")
        |> truncate_generated_title()
    end
  end

  defp truncate_generated_title(title) when title in [nil, ""], do: nil

  defp truncate_generated_title(title) do
    shortened_title =
      if String.length(title) <= 60 do
        title
      else
        title
        |> String.slice(0, 60)
        |> String.replace(~r/\s+\S*$/u, "")
        |> case do
          "" -> String.slice(title, 0, 60)
          value -> value
        end
      end

    case String.trim(shortened_title) do
      "" -> nil
      value -> value
    end
  end

  defp persist_title_update(chat_room, callbacks, title) do
    if is_function(callbacks[:on_title_updated], 1) or is_pid(callbacks[:recipient]) do
      notify_title_updated(callbacks, title)
    else
      _ = Chat.update_chat_room_title(chat_room, title)
      :ok
    end
  end

  defp notify_title_updated(callbacks, title) do
    call_callback(
      callbacks[:on_title_updated],
      [title],
      fn recipient ->
        send(recipient, {:chatroom_title_updated, title})
      end,
      callbacks[:recipient]
    )
  end

  defp agent_runner, do: Application.get_env(:app, :agent_runner, App.Agents.Runner)
end
