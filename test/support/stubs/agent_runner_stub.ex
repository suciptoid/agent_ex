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

  def run_streaming(agent, messages, recipient, opts \\ []) do
    content = stub_content(agent, messages)
    emit_chunk = stream_callback(recipient, opts)

    content
    |> String.graphemes()
    |> Enum.each(emit_chunk)

    {:ok,
     %{content: content, usage: %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}}}
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
