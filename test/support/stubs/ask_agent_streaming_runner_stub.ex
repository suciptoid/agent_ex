defmodule App.TestSupport.AskAgentStreamingRunnerStub do
  def run(agent, messages, opts \\ []) do
    App.TestSupport.AgentRunnerStub.run(agent, messages, opts)
  end

  def run_streaming(agent, _messages, recipient, opts \\ []) do
    emit_chunk =
      stream_callback(recipient, opts, :on_result, fn token -> {:stream_chunk, token} end)

    emit_tool_calls =
      stream_callback(recipient, opts, :on_tool_calls, fn tool_call_turn ->
        {:stream_tool_calls, tool_call_turn}
      end)

    emit_tool_start =
      stream_callback(recipient, opts, :on_tool_start, fn tool_result ->
        {:stream_tool_started, tool_result}
      end)

    emit_tool_result =
      stream_callback(recipient, opts, :on_tool_result, fn tool_result ->
        {:stream_tool_result, tool_result}
      end)

    if delegated_tool_run?(opts) do
      content = "I'll ask the delegated agent to handle that."
      ask_agent_tool = Enum.find(opts[:extra_tools] || [], &(&1.name == "ask_agent"))
      delegated_agent_id = delegated_agent_id(opts[:extra_system_prompt] || "")

      tool_result = %{
        "id" => "tool_ask_agent",
        "name" => "ask_agent",
        "arguments" => %{"agent_id" => delegated_agent_id, "instructions" => "Fetch the facts."},
        "content" => "Asked the delegated agent to continue.",
        "status" => "ok"
      }

      {:ok, _result} =
        ReqLLM.Tool.execute(ask_agent_tool, %{
          "agent_id" => delegated_agent_id,
          "instructions" => "Fetch the facts."
        })

      emit_tool_calls.(%{
        "content" => content,
        "tool_calls" => [
          %{
            "id" => tool_result["id"],
            "name" => tool_result["name"],
            "arguments" => tool_result["arguments"]
          }
        ]
      })

      emit_tool_start.(Map.put(tool_result, "content", nil) |> Map.put("status", "running"))
      emit_tool_result.(tool_result)

      content
      |> String.graphemes()
      |> Enum.each(emit_chunk)

      {:ok, result(content)}
    else
      content = "#{agent.name}: fetched delegated payload"

      content
      |> String.graphemes()
      |> Enum.each(emit_chunk)

      {:ok, result(content)}
    end
  end

  defp delegated_tool_run?(opts) do
    Enum.any?(opts[:extra_tools] || [], &(&1.name == "ask_agent"))
  end

  defp delegated_agent_id(extra_system_prompt) do
    case Regex.scan(~r/\(id: ([^)]+)\)/, extra_system_prompt) |> List.last() do
      [_, agent_id] -> agent_id
      _ -> raise "could not extract delegated agent id from system prompt"
    end
  end

  defp result(content) do
    %{
      content: content,
      usage: %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2},
      thinking: nil,
      tool_responses: [],
      finish_reason: "stop",
      provider_meta: %{}
    }
  end

  defp stream_callback(recipient, opts, key, default_message_builder) do
    case Keyword.get(opts, key) do
      callback when is_function(callback, 1) ->
        callback

      _ when is_pid(recipient) ->
        fn payload -> send(recipient, default_message_builder.(payload)) end

      _ ->
        fn _payload -> :ok end
    end
  end
end
