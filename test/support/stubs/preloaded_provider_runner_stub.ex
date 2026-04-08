defmodule App.TestSupport.PreloadedProviderRunnerStub do
  alias App.Agents.Agent
  alias App.Providers.Provider

  def run(agent, messages, _opts \\ [])

  def run(%Agent{provider: %Provider{}} = agent, messages, _opts) do
    notify(agent, messages)
    {:ok, result(stub_content(agent, messages))}
  end

  def run(%Agent{}, _messages, _opts), do: {:error, "agent provider must be preloaded"}

  def run_streaming(agent, messages, recipient, opts \\ [])

  def run_streaming(%Agent{provider: %Provider{}} = agent, messages, recipient, opts) do
    content = stub_content(agent, messages)

    notify(agent, messages)

    emit_chunk =
      case Keyword.get(opts, :on_result) do
        callback when is_function(callback, 1) ->
          callback

        _ when is_pid(recipient) ->
          fn token -> send(recipient, {:stream_chunk, token}) end

        _ ->
          fn _token -> :ok end
      end

    Enum.each(String.graphemes(content), emit_chunk)

    {:ok, result(content)}
  end

  def run_streaming(%Agent{}, _messages, _recipient, _opts),
    do: {:error, "agent provider must be preloaded"}

  defp stub_content(agent, messages) do
    case Enum.find(Enum.reverse(messages), &(&1.role == "user")) do
      nil -> "#{agent.name} is ready."
      message -> "#{agent.name}: #{message.content}"
    end
  end

  defp notify(agent, messages) do
    case Application.get_env(:app, __MODULE__, []) |> Keyword.get(:notify_pid) do
      notify_pid when is_pid(notify_pid) ->
        send(notify_pid, {:preloaded_provider_runner_called, agent, messages})

      _other ->
        :ok
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
end
