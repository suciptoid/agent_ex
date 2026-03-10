defmodule App.TestSupport.DelegatingAgentRunnerStub do
  def run(agent, messages, opts \\ []) do
    App.TestSupport.AgentRunnerStub.run(agent, messages, opts)
  end

  def run_streaming(agent, _messages, recipient, opts \\ []) do
    emit_chunk = stream_callback(recipient, opts)

    if delegated_tool_run?(opts) do
      content = "I'll ask the delegated agent to handle that."
      emit_text(content, emit_chunk)

      ask_agent_tool = Enum.find(opts[:extra_tools] || [], &(&1.name == "ask_agent"))
      delegated_agent_id = delegated_agent_id(opts[:extra_system_prompt] || "")

      {:ok, _result} =
        ReqLLM.Tool.execute(ask_agent_tool, %{
          "agent_id" => delegated_agent_id,
          "instructions" => "Fetch the delegated payload."
        })

      {:ok,
       %{
         content: content,
         usage: %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
       }}
    else
      maybe_wait_for_release(agent)

      content = "#{agent.name}: fetched delegated payload"
      emit_text(content, emit_chunk)

      {:ok,
       %{
         content: content,
         usage: %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
       }}
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

  defp maybe_wait_for_release(agent) do
    case Application.get_env(:app, :delegating_agent_test_pid) do
      test_pid when is_pid(test_pid) ->
        send(test_pid, {:delegated_agent_started, self(), agent.id})

        receive do
          :continue_delegated_agent -> :ok
        after
          1_000 -> :ok
        end

      _ ->
        :ok
    end
  end

  defp emit_text(content, emit_chunk) do
    content
    |> String.graphemes()
    |> Enum.each(emit_chunk)
  end

  defp stream_callback(recipient, opts) do
    case Keyword.get(opts, :on_result) do
      callback when is_function(callback, 1) ->
        callback

      _ when is_pid(recipient) ->
        fn token -> send(recipient, {:stream_chunk, token}) end

      _ ->
        fn _token -> :ok end
    end
  end
end
