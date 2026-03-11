defmodule App.TestSupport.SlowStreamingRunnerStub do
  def run(agent, messages, _opts \\ []) do
    {:ok, result(stub_content(agent, messages))}
  end

  def run_streaming(agent, messages, recipient, opts \\ []) do
    content = stub_content(agent, messages)

    emit_chunk =
      stream_callback(recipient, opts, :on_result, fn token -> {:stream_chunk, token} end)

    notify_pid = Application.get_env(:app, __MODULE__, []) |> Keyword.get(:notify_pid)

    if is_pid(notify_pid) do
      send(notify_pid, {:slow_runner_started, self()})
    end

    case String.graphemes(content) do
      [] ->
        :ok

      [first_chunk | _rest] ->
        emit_chunk.(first_chunk)
    end

    receive do
      :continue ->
        content
        |> String.graphemes()
        |> Enum.drop(1)
        |> Enum.each(emit_chunk)

        {:ok, result(content)}
    after
      5_000 ->
        {:error, "slow stream timed out"}
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

  defp stub_content(agent, messages) do
    last_user_message = messages |> Enum.reverse() |> Enum.find(&(&1.role == "user"))

    case last_user_message do
      nil -> "#{agent.name} is ready."
      message -> "#{agent.name}: #{message.content}"
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
