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
           {:ok, agent} <- commander_agent(chat_room) do
        Logger.debug("[Orchestrator] Running agent #{agent.name} (#{agent.id})")

        run_opts = multi_agent_opts(chat_room, messages)

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
  Streams a response from the commander agent for the given messages to `lv_pid`.

  The user message should already be present in `messages`.
  Sends `{:stream_chunk, token}` to `lv_pid` and returns
  `{:ok, %{content:, agent_id:, metadata:}}` on success.
  """
  def stream_message(%ChatRoom{} = chat_room, messages, lv_pid) when is_pid(lv_pid) do
    with {:ok, agent} <- commander_agent(chat_room) do
      Logger.debug("[Orchestrator] Streaming agent #{agent.name} (#{agent.id})")
      run_opts = multi_agent_opts(chat_room, messages)

      case agent_runner().run_streaming(agent, messages, lv_pid, run_opts) do
        {:ok, %{content: content, usage: usage}} ->
          {:ok, %{content: content, agent_id: agent.id, metadata: %{"usage" => usage}}}

        {:error, reason} ->
          Logger.error("[Orchestrator] Streaming failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp commander_agent(%ChatRoom{chat_room_agents: chat_room_agents}) do
    case Enum.find(chat_room_agents, & &1.is_commander) || List.first(chat_room_agents) do
      %ChatRoomAgent{agent: agent} -> {:ok, agent}
      nil -> {:error, "This chat room has no agents assigned"}
    end
  end

  # Returns extra opts for multi-agent rooms: system prompt roster + handover tool
  defp multi_agent_opts(%ChatRoom{chat_room_agents: chat_room_agents}, messages) do
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
      You are the commander agent. Other agents available in this room:
      #{agent_roster}

      To delegate a subtask to another agent, use the `handover` tool with the agent's id and clear instructions.
      The handover tool runs that agent and returns its response for you to incorporate in your final answer.
      """

      [
        extra_system_prompt: extra_prompt,
        extra_tools: [build_handover_tool(agents, messages)]
      ]
    end
  end

  defp build_handover_tool(agents, current_messages) do
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
      name: "handover",
      description:
        "Delegate a subtask to another agent and get their response. Available agents: #{agent_descriptions}",
      parameter_schema: [
        agent_id: [type: :string, required: true, doc: "The id of the agent to delegate to"],
        instructions: [
          type: :string,
          required: true,
          doc: "Clear instructions for the target agent"
        ]
      ],
      callback: fn args ->
        agent_id = Map.get(args, :agent_id) || Map.get(args, "agent_id")
        instructions = Map.get(args, :instructions) || Map.get(args, "instructions")

        case Map.get(agent_map, to_string(agent_id)) do
          nil ->
            {:error, "Unknown agent_id: #{agent_id}"}

          target_agent ->
            Logger.info("[Orchestrator] Handover to agent #{target_agent.name} (#{agent_id})")
            sub_messages = messages_snapshot ++ [%{role: "user", content: instructions}]

            case App.Agents.Runner.run(target_agent, sub_messages) do
              {:ok, response} ->
                result = ReqLLM.Response.text(response) || "Agent returned empty response."
                Logger.debug("[Orchestrator] Handover result: #{String.slice(result, 0, 200)}")
                {:ok, result}

              {:error, reason} ->
                {:error, "Agent #{target_agent.name} failed: #{inspect(reason)}"}
            end
        end
      end
    )
  end

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
