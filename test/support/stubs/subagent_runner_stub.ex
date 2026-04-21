defmodule App.TestSupport.SubagentRunnerStub do
  def run(agent, messages, opts \\ []) do
    App.TestSupport.AgentRunnerStub.run(agent, messages, opts)
  end

  def run_streaming(agent, _messages, recipient, opts \\ []) do
    emit_chunk =
      stream_callback(recipient, opts, :on_result, fn token -> {:stream_chunk, token} end)

    if subagent_tools_run?(opts) do
      alloy_context = Keyword.get(opts, :alloy_context, %{})
      target_agent_id = delegated_agent_id(alloy_context)

      {:ok, listed_agents_response} =
        App.Agents.AlloyTools.SubagentLists.execute(%{}, alloy_context)

      listed_agents = Jason.decode!(listed_agents_response)["agents"]
      assert_listed_agent!(listed_agents, target_agent_id)

      {:ok, spawn_response} =
        App.Agents.AlloyTools.SubagentSpawn.execute(
          %{
            "agent_id" => target_agent_id,
            "prompt" => "Fetch the delegated payload."
          },
          alloy_context
        )

      %{"subagent_id" => subagent_id} = Jason.decode!(spawn_response)

      {:ok, _wait_response} =
        App.Agents.AlloyTools.SubagentWait.execute(
          %{"subagent_id" => subagent_id},
          alloy_context
        )

      content = "#{agent.name}: integrated subagent payload"

      content
      |> String.graphemes()
      |> Enum.each(emit_chunk)

      {:ok, result(content)}
    else
      content = "#{agent.name}: fetched subagent payload"

      content
      |> String.graphemes()
      |> Enum.each(emit_chunk)

      {:ok, result(content)}
    end
  end

  defp subagent_tools_run?(opts) do
    tool_names =
      opts[:extra_tools] || []

    Enum.any?(tool_names, &(&1 == App.Agents.AlloyTools.SubagentLists)) and
      Enum.any?(tool_names, &(&1 == App.Agents.AlloyTools.SubagentSpawn)) and
      Enum.any?(tool_names, &(&1 == App.Agents.AlloyTools.SubagentWait))
  end

  defp delegated_agent_id(alloy_context) do
    current_agent_id = Map.get(alloy_context, :current_agent_id)

    alloy_context
    |> Map.get(:agents, [])
    |> Enum.map(& &1.id)
    |> Enum.find(&(&1 != current_agent_id))
    |> case do
      nil -> raise "could not extract delegated agent id from context"
      agent_id -> agent_id
    end
  end

  defp assert_listed_agent!(listed_agents, target_agent_id) do
    if Enum.any?(listed_agents, &(Map.get(&1, "agent_id") == target_agent_id)) do
      :ok
    else
      raise "expected subagent_lists to include delegated agent #{target_agent_id}"
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
