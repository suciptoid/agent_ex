defmodule App.Providers.OpenAICompatStream do
  @moduledoc false

  alias Alloy.Message
  alias Alloy.Provider.SSE

  @spec stream(
          String.t(),
          [{String.t(), String.t()}],
          map(),
          (String.t() -> any()),
          keyword(),
          (term() -> any())
        ) ::
          {:ok, Alloy.Provider.completion_response()} | {:error, term()}
  def stream(url, headers, body, on_chunk, req_options, on_event)
      when is_function(on_chunk, 1) and is_function(on_event, 1) do
    body =
      body
      |> Map.put("stream", true)
      |> Map.put("stream_options", %{"include_usage" => true})

    initial_acc = %{
      buffer: "",
      content: "",
      reasoning_content: "",
      tool_calls: %{},
      finish_reason: nil,
      usage: %{},
      on_chunk: on_chunk,
      on_event: on_event
    }

    stream_handler = SSE.req_stream_handler(initial_acc, &handle_event/2)

    req_opts =
      ([
         url: url,
         method: :post,
         headers: headers,
         body: Jason.encode!(body),
         into: stream_handler
       ] ++ req_options)
      |> Keyword.put(:retry, false)

    case Req.request(req_opts) do
      {:ok, %{status: 200} = resp} ->
        resp
        |> Map.get(:private, %{})
        |> Map.get(:sse_acc, initial_acc)
        |> build_response()

      {:ok, %{status: status} = resp} ->
        {:error, parse_error(status, streaming_error_body(resp, initial_acc))}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp streaming_error_body(resp, initial_acc) do
    case resp.body do
      "" ->
        resp
        |> Map.get(:private, %{})
        |> Map.get(:sse_acc, initial_acc)
        |> Map.get(:buffer)

      body ->
        body
    end
  end

  defp handle_event(acc, %{data: "[DONE]"}), do: acc

  defp handle_event(acc, %{data: data}) do
    case Jason.decode(data) do
      {:ok, parsed} -> process_event(acc, parsed)
      {:error, _reason} -> acc
    end
  end

  defp process_event(acc, %{"choices" => [%{"delta" => delta} | _]} = event) do
    acc =
      case delta do
        %{"content" => text} when is_binary(text) and text != "" ->
          acc.on_chunk.(text)
          %{acc | content: acc.content <> text}

        _other ->
          acc
      end

    acc =
      case reasoning_delta(delta) do
        text when is_binary(text) and text != "" ->
          acc.on_event.({:thinking_delta, text})
          %{acc | reasoning_content: acc.reasoning_content <> text}

        _other ->
          acc
      end

    acc = accumulate_tool_calls(acc, Map.get(delta, "tool_calls", []))

    case event do
      %{"choices" => [%{"finish_reason" => reason} | _]} when is_binary(reason) ->
        %{acc | finish_reason: reason}

      _other ->
        acc
    end
  end

  defp process_event(acc, %{"choices" => [], "usage" => usage}) when is_map(usage) do
    %{acc | usage: usage}
  end

  defp process_event(acc, %{"usage" => usage}) when is_map(usage) do
    %{acc | usage: usage}
  end

  defp process_event(acc, _event), do: acc

  defp reasoning_delta(delta) do
    Map.get(delta, "reasoning_content") ||
      Map.get(delta, "reasoning") ||
      Map.get(delta, "thinking_content") ||
      Map.get(delta, "thinking")
  end

  defp accumulate_tool_calls(acc, []), do: acc

  defp accumulate_tool_calls(acc, tool_call_deltas) do
    tool_calls =
      Enum.reduce(tool_call_deltas, acc.tool_calls, fn tc_delta, tool_calls ->
        index = tc_delta["index"]
        existing = Map.get(tool_calls, index, %{id: nil, name: nil, arguments_buffer: ""})

        existing =
          case tc_delta do
            %{"id" => id} -> %{existing | id: id}
            _other -> existing
          end

        existing =
          case get_in(tc_delta, ["function", "name"]) do
            nil -> existing
            name -> %{existing | name: name}
          end

        existing =
          case get_in(tc_delta, ["function", "arguments"]) do
            nil -> existing
            args -> %{existing | arguments_buffer: existing.arguments_buffer <> args}
          end

        Map.put(tool_calls, index, existing)
      end)

    %{acc | tool_calls: tool_calls}
  end

  defp build_response(acc) do
    reasoning_blocks =
      if acc.reasoning_content != "",
        do: [%{type: "thinking", thinking: acc.reasoning_content}],
        else: []

    text_blocks = if acc.content != "", do: [%{type: "text", text: acc.content}], else: []

    with {:ok, tool_blocks} <- build_tool_blocks(acc.tool_calls) do
      content_blocks = reasoning_blocks ++ text_blocks ++ tool_blocks

      {:ok,
       %{
         stop_reason: parse_finish_reason(acc.finish_reason),
         messages: [%Message{role: :assistant, content: content_blocks}],
         usage: %{
           input_tokens: Map.get(acc.usage, "prompt_tokens", 0),
           output_tokens: Map.get(acc.usage, "completion_tokens", 0)
         }
       }}
    end
  end

  defp build_tool_blocks(tool_calls) do
    tool_calls
    |> Enum.sort_by(fn {index, _call} -> index end)
    |> Enum.reduce_while({:ok, []}, fn {_index, tc}, {:ok, blocks} ->
      input_result =
        case tc.arguments_buffer do
          "" -> {:ok, %{}}
          args -> Jason.decode(args)
        end

      case input_result do
        {:ok, input} ->
          block = %{type: "tool_use", id: tc.id, name: tc.name, input: input}
          {:cont, {:ok, blocks ++ [block]}}

        {:error, reason} ->
          {:halt, {:error, "Invalid tool call JSON for #{tc.name}: #{inspect(reason)}"}}
      end
    end)
  end

  defp parse_finish_reason("stop"), do: :end_turn
  defp parse_finish_reason("tool_calls"), do: :tool_use
  defp parse_finish_reason("length"), do: :end_turn
  defp parse_finish_reason("content_filter"), do: :end_turn
  defp parse_finish_reason(_reason), do: :end_turn

  defp parse_error(status, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => error}} -> "#{error["type"]}: #{error["message"]}"
      _other -> "HTTP #{status}: #{body}"
    end
  end

  defp parse_error(status, body) when is_map(body) do
    case body do
      %{"error" => error} -> "#{error["type"]}: #{error["message"]}"
      _other -> "HTTP #{status}: #{inspect(body)}"
    end
  end
end
