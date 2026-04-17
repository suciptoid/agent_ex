defmodule App.Providers.OpenAICompat do
  @moduledoc """
  OpenAI-compatible Alloy provider with live reasoning delta events.
  """

  @behaviour Alloy.Provider

  alias Alloy.Message
  alias App.Providers.OpenAICompatStream

  @default_max_tokens 4096
  @default_chat_path "/v1/chat/completions"

  @impl true
  def complete(messages, tool_defs, config) do
    Alloy.Provider.OpenAICompat.complete(messages, tool_defs, config)
  end

  @impl true
  def stream(messages, tool_defs, config, on_chunk) when is_function(on_chunk, 1) do
    body = build_request_body(messages, tool_defs, config)
    url = "#{config.api_url}#{Map.get(config, :chat_path, @default_chat_path)}"
    on_event = Map.get(config, :on_event, fn _event -> :ok end)

    OpenAICompatStream.stream(
      url,
      build_headers(config),
      body,
      on_chunk,
      Map.get(config, :req_options, []),
      on_event
    )
  end

  defp build_headers(config) do
    base = [{"content-type", "application/json"}]

    base =
      case Map.get(config, :api_key) do
        nil -> base
        key -> [{"authorization", "Bearer #{key}"} | base]
      end

    base ++ Map.get(config, :extra_headers, [])
  end

  defp build_request_body(messages, tool_defs, config) do
    body = %{
      "model" => config.model,
      "max_tokens" => Map.get(config, :max_tokens, @default_max_tokens),
      "messages" => build_messages(messages, config)
    }

    body =
      case tool_defs do
        [] -> body
        defs -> Map.put(body, "tools", Enum.map(defs, &format_tool_def/1))
      end

    Map.merge(body, Map.get(config, :extra_body, %{}))
  end

  defp build_messages(messages, config) do
    system_msgs =
      case Map.get(config, :system_prompt) do
        nil -> []
        prompt -> [%{"role" => "system", "content" => prompt}]
      end

    system_msgs ++ Enum.flat_map(messages, &format_message/1)
  end

  defp format_message(%Message{role: :user, content: content}) when is_binary(content) do
    [%{"role" => "user", "content" => content}]
  end

  defp format_message(%Message{role: :assistant, content: content}) when is_binary(content) do
    [%{"role" => "assistant", "content" => content}]
  end

  defp format_message(%Message{role: :assistant, content: blocks}) when is_list(blocks) do
    tool_calls =
      blocks
      |> Enum.filter(&(&1[:type] == "tool_use"))
      |> Enum.map(fn call ->
        %{
          "id" => call.id,
          "type" => "function",
          "function" => %{
            "name" => call.name,
            "arguments" => Jason.encode!(call.input)
          }
        }
      end)

    text_parts =
      blocks
      |> Enum.filter(&(&1[:type] == "text"))
      |> Enum.map_join("\n", & &1.text)

    msg =
      if text_parts == "" do
        %{"role" => "assistant", "content" => nil}
      else
        %{"role" => "assistant", "content" => text_parts}
      end

    [if(tool_calls == [], do: msg, else: Map.put(msg, "tool_calls", tool_calls))]
  end

  defp format_message(%Message{role: :user, content: blocks}) when is_list(blocks) do
    if Enum.any?(blocks, &(&1[:type] == "tool_result")) do
      Enum.flat_map(blocks, fn
        %{type: "tool_result", tool_use_id: id, content: content} ->
          [%{"role" => "tool", "tool_call_id" => id, "content" => content}]

        _block ->
          []
      end)
    else
      parts = blocks |> Enum.map(&format_user_content_block/1) |> Enum.reject(&is_nil/1)
      [%{"role" => "user", "content" => parts}]
    end
  end

  defp format_user_content_block(%{type: "text", text: text}),
    do: %{"type" => "text", "text" => text}

  defp format_user_content_block(%{type: "image", mime_type: mime, data: data}),
    do: %{"type" => "image_url", "image_url" => %{"url" => "data:#{mime};base64,#{data}"}}

  defp format_user_content_block(_block), do: nil

  defp format_tool_def(%{name: name, description: desc, input_schema: schema}) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => desc,
        "parameters" => Alloy.Provider.stringify_keys(schema)
      }
    }
  end
end
