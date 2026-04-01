defmodule App.Chat.Orchestrator do
  @moduledoc """
  Handles message orchestration for chat rooms.
  """

  require Logger

  alias App.Chat
  alias App.Chat.{ChatRoom, ChatRoomAgent}

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

        run_opts = multi_agent_opts(chat_room, messages, nil)

        case agent_runner().run(agent, messages, run_opts) do
          {:ok, result} ->
            assistant_content = result.content || "The agent returned an empty response."

            Logger.info(
              "[Orchestrator] Got response, length: #{String.length(assistant_content)}"
            )

            Chat.create_message(chat_room, %{
              role: "assistant",
              content: assistant_content,
              agent_id: agent.id,
              metadata: response_metadata(result)
            })

          {:error, reason} ->
            Logger.error("[Orchestrator] Agent run failed: #{inspect(reason)}")
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
        |> Keyword.merge(callback_run_opts(callbacks))

      case agent_runner().run_streaming(agent, messages, callbacks[:recipient], run_opts) do
        {:ok, result} ->
          {:ok,
           %{
             content: result.content,
             agent_id: agent.id,
             metadata: response_metadata(result)
           }}

        {:error, reason} ->
          Logger.error("[Orchestrator] Streaming failed: #{inspect(reason)}")
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

      [
        extra_system_prompt: extra_prompt,
        extra_tools: [
          build_handover_tool(chat_room, agents, callbacks),
          build_ask_agent_tool(chat_room, agents, messages, callbacks)
        ]
      ]
    end
  end

  defp build_handover_tool(chat_room, agents, callbacks) do
    agent_descriptions =
      agents
      |> Enum.map(fn a ->
        desc =
          if blank?(a.system_prompt),
            do: "general assistant",
            else: String.slice(a.system_prompt, 0, 80)

        "#{a.name} (id: #{a.id}) - #{desc}"
      end)
      |> Enum.join("; ")

    agent_map = Map.new(agents, fn a -> {to_string(a.id), a} end)

    ReqLLM.tool(
      name: "handover",
      description:
        "Transfer the active agent role to another agent in this room. They will handle future messages. Available agents: #{agent_descriptions}",
      parameter_schema: [
        agent_id: [
          type: :string,
          required: true,
          doc: "The id of the agent to make active"
        ],
        reason: [
          type: :string,
          required: false,
          doc: "Optional reason for the handover"
        ]
      ],
      callback: fn args ->
        agent_id = Map.get(args, :agent_id) || Map.get(args, "agent_id")
        reason = Map.get(args, :reason) || Map.get(args, "reason")

        case Map.get(agent_map, to_string(agent_id)) do
          nil ->
            {:error, "Unknown agent_id: #{agent_id}"}

          target_agent ->
            Logger.info("[Orchestrator] Handover to agent #{target_agent.name} (#{agent_id})")

            case Chat.set_active_agent(chat_room, target_agent.id) do
              :ok ->
                notify_active_agent_changed(callbacks, target_agent.id)

                msg =
                  if blank?(reason),
                    do: "Handed over to #{target_agent.name}.",
                    else: "Handed over to #{target_agent.name}: #{reason}"

                {:ok, msg}

              {:error, err} ->
                {:error, "Failed to set active agent: #{inspect(err)}"}
            end
        end
      end
    )
  end

  defp build_ask_agent_tool(chat_room, agents, current_messages, callbacks) do
    agent_descriptions =
      agents
      |> Enum.map(fn a ->
        desc =
          if blank?(a.system_prompt),
            do: "general assistant",
            else: String.slice(a.system_prompt, 0, 80)

        "#{a.name} (id: #{a.id}) - #{desc}"
      end)
      |> Enum.join("; ")

    agent_map = Map.new(agents, fn a -> {to_string(a.id), a} end)
    messages_snapshot = current_messages

    ReqLLM.tool(
      name: "ask_agent",
      description:
        "Ask another agent to handle a specific task. The agent will respond and their message will appear in the chat. Available agents: #{agent_descriptions}",
      parameter_schema: [
        agent_id: [type: :string, required: true, doc: "The id of the agent to ask"],
        instructions: [
          type: :string,
          required: true,
          doc: "Clear instructions for the target agent"
        ]
      ],
      callback: fn args ->
        agent_id = Map.get(args, :agent_id) || Map.get(args, "agent_id")

        instructions =
          normalize_instruction_text(
            Map.get(args, :instructions) || Map.get(args, "instructions")
          )

        case Map.get(agent_map, to_string(agent_id)) do
          nil ->
            {:error, "Unknown agent_id: #{agent_id}"}

          target_agent ->
            Logger.info("[Orchestrator] ask_agent to #{target_agent.name} (#{agent_id})")

            placeholder_attrs = %{
              role: "assistant",
              content: nil,
              agent_id: target_agent.id,
              status: :pending,
              metadata: %{"delegated" => true, "tool_name" => "ask_agent"}
            }

            case Chat.create_message(chat_room, placeholder_attrs) do
              {:ok, placeholder_message} ->
                notify_agent_message_created(callbacks, placeholder_message)

                {:ok, _pid} =
                  Task.start(fn ->
                    run_delegated_agent(
                      chat_room,
                      target_agent,
                      messages_snapshot,
                      instructions,
                      placeholder_message,
                      callbacks
                    )
                  end)

                {:ok, "Asked #{target_agent.name} to handle that. They will reply in the chat."}

              {:error, reason} ->
                {:error, "Failed to start delegated agent: #{inspect(reason)}"}
            end
        end
      end
    )
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

    case agent_runner().run_streaming(target_agent, sub_messages, nil, stream_opts) do
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
          callbacks
        )

      {:error, reason} ->
        Logger.error(
          "[Orchestrator] Delegated agent #{target_agent.name} failed: #{inspect(reason)}"
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
          callbacks
        )
    end
  end

  defp persist_delegated_message(chat_room, placeholder_message, attrs, callbacks) do
    case Chat.get_message_by_id(placeholder_message.id) do
      nil ->
        case Chat.create_message(chat_room, Map.put_new(attrs, :role, "assistant")) do
          {:ok, message} ->
            notify_agent_message_created(callbacks, message)

          {:error, reason} ->
            Logger.error(
              "[Orchestrator] Failed to persist delegated message #{placeholder_message.id}: #{inspect(reason)}"
            )
        end

      existing_message ->
        case Chat.update_message(existing_message, attrs) do
          {:ok, message} ->
            notify_agent_message_updated(callbacks, message)

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

  defp delegated_error_text(%{message: message}) when is_binary(message), do: message
  defp delegated_error_text(reason) when is_binary(reason), do: reason

  defp delegated_error_text(reason) when is_atom(reason),
    do: Phoenix.Naming.humanize(to_string(reason))

  defp delegated_error_text(reason), do: inspect(reason)

  defp normalize_instruction_text(value) when is_binary(value), do: String.trim(value)
  defp normalize_instruction_text(value), do: value

  defp response_metadata(result) do
    %{}
    |> maybe_put_metadata("usage", result.usage)
    |> maybe_put_metadata("thinking", blank_to_nil(result.thinking))
    |> maybe_put_metadata("tool_responses", empty_list_to_nil(result.tool_responses))
    |> maybe_put_metadata("finish_reason", result.finish_reason)
    |> maybe_put_metadata("provider_meta", normalize_metadata(result.provider_meta))
  end

  defp normalize_metadata(nil), do: nil
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp empty_list_to_nil([]), do: nil
  defp empty_list_to_nil(value), do: value

  defp blank?(value), do: value in [nil, ""]

  defp normalize_stream_callbacks(recipient) when is_pid(recipient) do
    [
      recipient: recipient,
      on_result: nil,
      on_thinking: nil,
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
      on_tool_start: callbacks[:on_tool_start],
      on_tool_result: callbacks[:on_tool_result]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp notify_active_agent_changed(callbacks, agent_id) do
    call_callback(
      callbacks[:on_active_agent_changed],
      [agent_id],
      fn recipient ->
        send(recipient, {:active_agent_changed, agent_id})
      end,
      callbacks[:recipient]
    )
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

  defp agent_runner, do: Application.get_env(:app, :agent_runner, App.Agents.Runner)
end
