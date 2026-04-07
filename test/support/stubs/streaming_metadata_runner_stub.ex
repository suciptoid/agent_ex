defmodule App.TestSupport.StreamingMetadataRunnerStub do
  def run(agent, messages, _opts \\ []) do
    {:ok, result(agent, messages)}
  end

  def run_streaming(agent, messages, recipient, opts \\ []) do
    response = result(agent, messages)

    emit_chunk =
      stream_callback(recipient, opts, :on_result, fn token -> {:stream_chunk, token} end)

    emit_thinking =
      stream_callback(recipient, opts, :on_thinking, fn token ->
        {:stream_thinking_chunk, token}
      end)

    emit_tool_result =
      stream_callback(recipient, opts, :on_tool_result, fn tool_result ->
        {:stream_tool_result, tool_result}
      end)

    emit_tool_calls =
      stream_callback(recipient, opts, :on_tool_calls, fn tool_call_turn ->
        {:stream_tool_calls, tool_call_turn}
      end)

    emit_tool_start =
      stream_callback(recipient, opts, :on_tool_start, fn tool_result ->
        {:stream_tool_started, tool_result}
      end)

    running_tool =
      response.tool_responses
      |> List.first()
      |> Map.put("content", nil)
      |> Map.put("status", "running")

    emit_thinking.(tool_call_turn_thinking(response))
    emit_tool_calls.(List.first(response.tool_call_turns))
    emit_tool_start.(running_tool)
    Enum.each(response.tool_responses, emit_tool_result)
    emit_thinking.(response.thinking)

    response.content
    |> String.graphemes()
    |> Enum.each(emit_chunk)

    {:ok, response}
  end

  defp result(agent, messages) do
    last_user_message = messages |> Enum.reverse() |> Enum.find(&(&1.role == "user"))
    prompt = if last_user_message, do: last_user_message.content, else: "hello"

    tool_result = %{
      "id" => "tool_1",
      "name" => "web_fetch",
      "arguments" => %{"url" => "https://example.com/data.txt"},
      "content" => "sample payload",
      "status" => "ok"
    }

    %{
      content: "#{agent.name}: #{prompt}",
      usage: %{
        "input_tokens" => 1,
        "output_tokens" => 1,
        "total_tokens" => 2,
        "total_cost" => 0.0123
      },
      thinking: "Summarizing the fetched payload",
      tool_call_turns: [
        %{
          "thinking" => "Planning the lookup",
          "tool_calls" => [
            %{
              "id" => tool_result["id"],
              "name" => tool_result["name"],
              "arguments" => tool_result["arguments"]
            }
          ]
        }
      ],
      tool_responses: [tool_result],
      finish_reason: "stop",
      provider_meta: %{}
    }
  end

  defp tool_call_turn_thinking(response) do
    response.tool_call_turns
    |> List.first()
    |> case do
      %{"thinking" => thinking} -> thinking
      _other -> nil
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
