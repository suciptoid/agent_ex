defmodule App.TestSupport.OverflowAwareRunnerStub do
  def run(agent, messages, _opts \\ []) do
    notify(:sync, messages)

    if checkpoint_present?(messages) do
      {:ok, result(agent, messages)}
    else
      {:error, overflow_error()}
    end
  end

  def run_streaming(agent, messages, recipient, opts \\ []) do
    notify(:streaming, messages)

    if checkpoint_present?(messages) do
      content = stub_content(agent, messages)

      emit_chunk =
        stream_callback(recipient, opts, :on_result, fn token -> {:stream_chunk, token} end)

      Enum.each(String.graphemes(content), emit_chunk)
      {:ok, result(agent, messages)}
    else
      {:error, overflow_error()}
    end
  end

  defp checkpoint_present?(messages) do
    Enum.any?(messages, &((Map.get(&1, :role) || Map.get(&1, "role")) == "checkpoint"))
  end

  defp result(agent, messages) do
    content = stub_content(agent, messages)

    %{
      content: content,
      usage: %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2},
      thinking: nil,
      tool_responses: [],
      finish_reason: "stop",
      provider_meta: %{}
    }
  end

  defp stub_content(agent, messages) do
    case Enum.find(
           Enum.reverse(messages),
           &((Map.get(&1, :role) || Map.get(&1, "role")) == "user")
         ) do
      nil -> "#{agent.name} is ready."
      message -> "#{agent.name}: #{Map.get(message, :content) || Map.get(message, "content")}"
    end
  end

  defp overflow_error do
    "This endpoint's maximum context length is 131072 tokens. However, you requested about 167452 tokens."
  end

  defp notify(mode, messages) do
    case Application.get_env(:app, __MODULE__, []) |> Keyword.get(:notify_pid) do
      notify_pid when is_pid(notify_pid) ->
        send(notify_pid, {:overflow_runner_call, mode, messages})

      _other ->
        :ok
    end
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
