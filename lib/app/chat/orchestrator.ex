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
          {:ok, response} ->
            assistant_content =
              ReqLLM.Response.text(response) || "The agent returned an empty response."

            Logger.info(
              "[Orchestrator] Got response, length: #{String.length(assistant_content)}"
            )

            Chat.create_message(chat_room, %{
              role: "assistant",
              content: assistant_content,
              agent_id: agent.id,
              metadata: response_metadata(response)
            })

          {:error, reason} ->
            Logger.error("[Orchestrator] Agent run failed: #{inspect(reason)}")
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Streams a response from the active agent for the given messages to `lv_pid`.

  The user message should already be present in `messages`.
  Sends `{:stream_chunk, token}` to `lv_pid` and returns
  `{:ok, %{content:, agent_id:, metadata:}}` on success.
  """
  def stream_message(%ChatRoom{} = chat_room, messages, lv_pid) when is_pid(lv_pid) do
    with {:ok, agent} <- active_agent(chat_room) do
      Logger.debug("[Orchestrator] Streaming agent #{agent.name} (#{agent.id})")
      run_opts = multi_agent_opts(chat_room, messages, lv_pid)

      case agent_runner().run_streaming(agent, messages, lv_pid, run_opts) do
        {:ok, %{content: content, usage: usage}} ->
          {:ok, %{content: content, agent_id: agent.id, metadata: %{"usage" => usage}}}

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
         lv_pid
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
          build_handover_tool(chat_room, agents, lv_pid),
          build_ask_agent_tool(chat_room, agents, messages, lv_pid)
        ]
      ]
    end
  end

  defp build_handover_tool(chat_room, agents, lv_pid) do
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
                if is_pid(lv_pid), do: send(lv_pid, {:active_agent_changed, target_agent.id})

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

  defp build_ask_agent_tool(chat_room, agents, current_messages, lv_pid) do
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
              status: "requesting",
              metadata: %{"delegated" => true, "tool_name" => "ask_agent"}
            }

            case Chat.create_message(chat_room, placeholder_attrs) do
              {:ok, placeholder_message} ->
                if is_pid(lv_pid), do: send(lv_pid, {:agent_message_created, placeholder_message})

                {:ok, _pid} =
                  Task.start(fn ->
                    run_delegated_agent(
                      chat_room,
                      target_agent,
                      messages_snapshot,
                      instructions,
                      placeholder_message,
                      lv_pid
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
         lv_pid
       ) do
    sub_messages = messages_snapshot ++ [%{role: "user", content: instructions}]

    stream_opts = [
      on_result: fn token ->
        if is_pid(lv_pid) do
          send(lv_pid, {:agent_message_stream_chunk, placeholder_message.id, token})
        end
      end
    ]

    case agent_runner().run_streaming(target_agent, sub_messages, nil, stream_opts) do
      {:ok, %{content: content, usage: usage}} ->
        metadata = delegated_message_metadata(placeholder_message.metadata, usage: usage)

        persist_delegated_message(
          chat_room,
          placeholder_message,
          %{
            content: content,
            status: "completed",
            metadata: metadata,
            agent_id: target_agent.id
          },
          lv_pid
        )

      {:error, reason} ->
        Logger.error(
          "[Orchestrator] Delegated agent #{target_agent.name} failed: #{inspect(reason)}"
        )

        existing_message = Chat.get_message_by_id(placeholder_message.id)
        current_content = existing_message && existing_message.content

        metadata =
          delegated_message_metadata(placeholder_message.metadata,
            error: delegated_error_text(reason)
          )

        persist_delegated_message(
          chat_room,
          placeholder_message,
          %{
            content:
              if(blank?(current_content),
                do: "Agent #{target_agent.name} encountered an error.",
                else: current_content
              ),
            status: "error",
            metadata: metadata,
            agent_id: target_agent.id
          },
          lv_pid
        )
    end
  end

  defp persist_delegated_message(chat_room, placeholder_message, attrs, lv_pid) do
    case Chat.get_message_by_id(placeholder_message.id) do
      nil ->
        case Chat.create_message(chat_room, Map.put_new(attrs, :role, "assistant")) do
          {:ok, message} ->
            if is_pid(lv_pid), do: send(lv_pid, {:agent_message_created, message})

          {:error, reason} ->
            Logger.error(
              "[Orchestrator] Failed to persist delegated message #{placeholder_message.id}: #{inspect(reason)}"
            )
        end

      existing_message ->
        case Chat.update_message(existing_message, attrs) do
          {:ok, message} ->
            if is_pid(lv_pid), do: send(lv_pid, {:agent_message_updated, message})

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
    |> maybe_put_metadata("usage", Keyword.get(extra_attrs, :usage))
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

  defp response_metadata(response) do
    %{
      "usage" => normalize_metadata(ReqLLM.Response.usage(response)),
      "finish_reason" => response.finish_reason && to_string(response.finish_reason),
      "provider_meta" => normalize_metadata(response.provider_meta)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == %{} end)
    |> Map.new()
  end

  defp normalize_metadata(nil), do: nil
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp blank?(value), do: value in [nil, ""]

  defp agent_runner, do: Application.get_env(:app, :agent_runner, App.Agents.Runner)
end
