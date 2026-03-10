defmodule App.TestSupport.AgentRunnerStub do
  defp stub_content(agent, messages) do
    last_user_message = messages |> Enum.reverse() |> Enum.find(&(&1.role == "user"))

    case last_user_message do
      nil -> "#{agent.name} is ready."
      message -> "#{agent.name}: #{message.content}"
    end
  end

  def run(agent, messages, _opts \\ []) do
    content = stub_content(agent, messages)
    assistant_message = ReqLLM.Context.assistant(content)

    {:ok,
     %ReqLLM.Response{
       id: "stub-response",
       model: agent.model,
       context: ReqLLM.Context.new([assistant_message]),
       message: assistant_message,
       usage: %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2},
       finish_reason: :stop,
       provider_meta: %{}
     }}
  end

  def run_streaming(agent, messages, lv_pid, _opts \\ []) do
    content = stub_content(agent, messages)
    send(lv_pid, {:stream_chunk, content})

    {:ok,
     %{content: content, usage: %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}}}
  end
end
