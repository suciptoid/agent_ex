defmodule App.TestSupport.AgentRunnerStub do
  defp stub_content(agent, messages) do
    last_user_message = messages |> Enum.reverse() |> Enum.find(&(&1.role == "user"))

    case last_user_message do
      nil -> "#{agent.name} is ready."
      message -> "#{agent.name}: #{message.content}"
    end
  end

  def run(agent, messages, _opts \\ []) do
    {:ok, result(stub_content(agent, messages))}
  end

  def run_streaming(agent, messages, recipient, opts \\ []) do
    content = stub_content(agent, messages)

    emit_chunk =
      stream_callback(recipient, opts, :on_result, fn token -> {:stream_chunk, token} end)

    content
    |> String.graphemes()
    |> Enum.each(emit_chunk)

    {:ok, result(content)}
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
