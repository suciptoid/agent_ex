defmodule App.TestSupport.OutOfOrderToolStreamRunnerStub do
  def run(agent, messages, _opts \\ []) do
    {:ok, result(agent, messages)}
  end

  def run_streaming(agent, messages, recipient, opts \\ []) do
    response = result(agent, messages)

    emit_chunk =
      stream_callback(recipient, opts, :on_result, fn token -> {:stream_chunk, token} end)

    emit_tool_start =
      stream_callback(recipient, opts, :on_tool_start, fn tool_result ->
        {:stream_tool_started, tool_result}
      end)

    emit_tool_result =
      stream_callback(recipient, opts, :on_tool_result, fn tool_result ->
        {:stream_tool_result, tool_result}
      end)

    emit_tool_calls =
      stream_callback(recipient, opts, :on_tool_calls, fn tool_call_turn ->
        {:stream_tool_calls, tool_call_turn}
      end)

    [first_turn, second_turn] = response.tool_call_turns
    [first_tool, second_tool] = response.tool_responses

    emit_tool_calls.(first_turn)
    emit_tool_start.(running_tool(first_tool))

    emit_tool_calls.(second_turn)
    emit_tool_start.(running_tool(second_tool))

    emit_tool_result.(first_tool)
    emit_tool_result.(second_tool)
    emit_chunk.(response.content)

    {:ok, response}
  end

  defp result(agent, messages) do
    last_user_message = messages |> Enum.reverse() |> Enum.find(&(&1.role == "user"))
    prompt = if last_user_message, do: last_user_message.content, else: "hello"

    first_tool = %{
      "id" => "tool_topstories",
      "name" => "web_fetch",
      "arguments" => %{"url" => "https://hacker-news.firebaseio.com/v0/topstories.json"},
      "content" => "[47804965,47803844,47793411]",
      "status" => "ok"
    }

    second_tool = %{
      "id" => "tool_story",
      "name" => "web_fetch",
      "arguments" => %{"url" => "https://hacker-news.firebaseio.com/v0/item/47804965.json"},
      "content" => ~s({"title":"Example story"}),
      "status" => "ok"
    }

    %{
      content: "#{agent.name}: #{prompt}",
      usage: %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2},
      thinking: "Summarizing the stories",
      tool_call_turns: [
        tool_call_turn(first_tool, "Fetching top stories"),
        tool_call_turn(second_tool, "Fetching story details")
      ],
      tool_responses: [first_tool, second_tool],
      finish_reason: "stop",
      provider_meta: %{}
    }
  end

  defp running_tool(tool_response) do
    tool_response
    |> Map.put("content", nil)
    |> Map.put("status", "running")
  end

  defp tool_call_turn(tool_response, thinking) do
    %{
      "thinking" => thinking,
      "tool_calls" => [
        %{
          "id" => tool_response["id"],
          "name" => tool_response["name"],
          "arguments" => tool_response["arguments"]
        }
      ]
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
