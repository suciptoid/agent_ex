defmodule App.LLM.Client do
  @moduledoc false

  alias Alloy.Message
  alias App.LLM.ProviderConfig
  alias App.LLM.Tool
  alias App.Providers.Provider

  @type normalized_response :: %{
          type: :final_answer | :tool_calls,
          text: String.t(),
          thinking: String.t() | nil,
          tool_calls: [map()],
          finish_reason: String.t() | nil,
          usage: map() | nil,
          provider_meta: map() | nil,
          provider_state: map() | nil,
          assistant_message: map()
        }

  @spec stream(
          Provider.t(),
          String.t(),
          list(),
          [Tool.t()],
          keyword(),
          map()
        ) :: {:ok, normalized_response()} | {:error, term()}
  def stream(%Provider{} = provider, model, messages, tools, opts, callbacks)
      when is_binary(model) and is_list(messages) and is_list(tools) and is_list(opts) do
    on_result = callback(callbacks, :on_result)
    on_thinking = callback(callbacks, :on_thinking)

    on_event = fn
      {:thinking_delta, text} when is_binary(text) -> on_thinking.(text)
      %{event: :thinking_delta, payload: text} when is_binary(text) -> on_thinking.(text)
      _other -> :ok
    end

    opts = Keyword.put(opts, :on_event, on_event)
    {provider_module, provider_config} = ProviderConfig.resolve(provider, model, opts)
    adapter = ProviderConfig.adapter(provider)
    alloy_messages = to_alloy_messages(messages)
    tool_defs = Enum.map(tools, &tool_definition(&1, adapter))
    dbg({provider_module, provider_config})

    if function_exported?(provider_module, :stream, 4) do
      case provider_module.stream(alloy_messages, tool_defs, provider_config, on_result) do
        {:ok, response} -> {:ok, normalize_response(response)}
        {:error, reason} -> {:error, reason}
      end
    else
      with {:ok, response} <- provider_module.complete(alloy_messages, tool_defs, provider_config),
           normalized <- normalize_response(response) do
        if normalized.text != "" do
          on_result.(normalized.text)
        end

        if normalized.thinking not in [nil, ""] do
          on_thinking.(normalized.thinking)
        end

        {:ok, normalized}
      end
    end
  end

  @spec complete(Provider.t(), String.t(), list(), [Tool.t()], keyword()) ::
          {:ok, normalized_response()} | {:error, term()}
  def complete(%Provider{} = provider, model, messages, tools, opts \\ [])
      when is_binary(model) and is_list(messages) and is_list(tools) and is_list(opts) do
    {provider_module, provider_config} = ProviderConfig.resolve(provider, model, opts)
    adapter = ProviderConfig.adapter(provider)
    alloy_messages = to_alloy_messages(messages)
    tool_defs = Enum.map(tools, &tool_definition(&1, adapter))

    case provider_module.complete(alloy_messages, tool_defs, provider_config) do
      {:ok, response} -> {:ok, normalize_response(response)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec generate_text(Provider.t(), String.t(), list(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_text(%Provider{} = provider, model, messages, opts \\ [])
      when is_binary(model) and is_list(messages) and is_list(opts) do
    case complete(provider, model, messages, [], opts) do
      {:ok, %{text: text}} ->
        text = String.trim(text || "")

        if text == "" do
          {:error, :empty_response}
        else
          {:ok, text}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec normalize_response(map()) :: normalized_response()
  def normalize_response(response) when is_map(response) do
    assistant_message = extract_assistant_message(response)
    {text, thinking, tool_calls} = extract_message_parts(assistant_message)
    stop_reason = map_get(response, :stop_reason)

    type =
      case {tool_calls, stop_reason} do
        {[_ | _], _} -> :tool_calls
        {[], :tool_use} -> :tool_calls
        _other -> :final_answer
      end

    %{
      type: type,
      text: text,
      thinking: blank_to_nil(thinking),
      tool_calls: tool_calls,
      finish_reason: finish_reason(stop_reason),
      usage: normalize_usage(map_get(response, :usage)),
      provider_meta: normalize_metadata(map_get(response, :response_metadata)),
      provider_state: normalize_metadata(map_get(response, :provider_state)),
      assistant_message: assistant_message_for_context(text, tool_calls)
    }
  end

  defp callback(callbacks, key) do
    case Map.get(callbacks, key) do
      function when is_function(function, 1) -> function
      _other -> fn _value -> :ok end
    end
  end

  defp tool_definition(%Tool{} = tool, adapter) do
    %{
      name: tool.name,
      description: tool.description,
      input_schema: sanitize_input_schema(tool.input_schema, adapter)
    }
  end

  defp sanitize_input_schema(schema, adapter) when adapter in ["google", "gemini"] do
    sanitize_gemini_schema(schema)
  end

  defp sanitize_input_schema(schema, _adapter), do: schema

  defp sanitize_gemini_schema(%{} = schema) do
    schema
    |> Enum.reject(fn {key, _value} -> to_string(key) == "additionalProperties" end)
    |> Map.new(fn {key, value} -> {key, sanitize_gemini_schema(value)} end)
  end

  defp sanitize_gemini_schema(schema) when is_list(schema) do
    Enum.map(schema, &sanitize_gemini_schema/1)
  end

  defp sanitize_gemini_schema(schema), do: schema

  defp to_alloy_messages(messages) do
    messages
    |> Enum.flat_map(&to_alloy_message/1)
    |> Enum.reject(&is_nil/1)
  end

  defp to_alloy_message(message) do
    role = to_string(map_get(message, :role) || "user")
    content = map_get(message, :content)
    tool_calls = List.wrap(map_get(message, :tool_calls))

    case role do
      "assistant" ->
        assistant_to_alloy_message(content, tool_calls)

      "tool" ->
        tool_to_alloy_message(message)

      "system" ->
        [Message.user(system_like_content("system", content))]

      "checkpoint" ->
        [Message.user(system_like_content("checkpoint", content))]

      _other ->
        [Message.user(to_string(content || ""))]
    end
  end

  defp assistant_to_alloy_message(content, []), do: [Message.assistant(to_string(content || ""))]

  defp assistant_to_alloy_message(content, tool_calls) do
    blocks =
      []
      |> maybe_append_assistant_text(content)
      |> Kernel.++(Enum.map(tool_calls, &tool_use_block/1))

    [Message.assistant_blocks(blocks)]
  end

  defp tool_to_alloy_message(message) do
    tool_call_id = to_string(map_get(message, :tool_call_id) || random_id("tool_call"))
    content = to_string(map_get(message, :content) || "")
    is_error = tool_message_error?(message)

    [Message.tool_results([Message.tool_result_block(tool_call_id, content, is_error)])]
  end

  defp maybe_append_assistant_text(blocks, content) do
    case to_string(content || "") do
      "" -> blocks
      text -> blocks ++ [%{type: "text", text: text}]
    end
  end

  defp tool_use_block(tool_call) do
    %{
      type: "tool_use",
      id: to_string(map_get(tool_call, :id) || random_id("tool")),
      name: to_string(map_get(tool_call, :name) || "tool"),
      input: map_get(tool_call, :arguments) || %{}
    }
  end

  defp tool_message_error?(message) do
    metadata = map_get(message, :metadata)

    case metadata do
      %{"tool_status" => "error"} -> true
      %{tool_status: "error"} -> true
      _other -> false
    end
  end

  defp system_like_content(type, content) do
    body = to_string(content || "")
    "[#{String.upcase(type)}]\n" <> body
  end

  defp extract_assistant_message(response) do
    response
    |> map_get(:messages, [])
    |> List.wrap()
    |> Enum.reverse()
    |> Enum.find(%Message{role: :assistant, content: ""}, fn
      %Message{role: :assistant} -> true
      _other -> false
    end)
  end

  defp extract_message_parts(%Message{content: content}) when is_binary(content) do
    {content, nil, []}
  end

  defp extract_message_parts(%Message{content: blocks}) when is_list(blocks) do
    text =
      blocks
      |> Enum.filter(&(&1[:type] == "text"))
      |> Enum.map_join("", &to_string(&1[:text] || ""))

    thinking =
      blocks
      |> Enum.filter(&(&1[:type] == "thinking"))
      |> Enum.map_join("", &to_string(&1[:thinking] || ""))

    tool_calls =
      blocks
      |> Enum.filter(&(&1[:type] in ["tool_use", "server_tool_use"]))
      |> Enum.map(fn block ->
        %{
          id: to_string(block[:id] || random_id("tool")),
          name: to_string(block[:name] || "tool"),
          arguments: block[:input] || %{}
        }
      end)

    {text, thinking, tool_calls}
  end

  defp extract_message_parts(_message), do: {"", nil, []}

  defp assistant_message_for_context(text, tool_calls) do
    %{}
    |> Map.put(:role, "assistant")
    |> maybe_put(:content, blank_to_nil(text))
    |> maybe_put(:tool_calls, if(tool_calls == [], do: nil, else: tool_calls))
  end

  defp finish_reason(:tool_use), do: "tool_calls"
  defp finish_reason(:end_turn), do: "stop"
  defp finish_reason(nil), do: nil
  defp finish_reason(reason), do: to_string(reason)

  defp normalize_usage(nil), do: nil

  defp normalize_usage(usage) when is_map(usage) do
    normalized_usage =
      usage
      |> normalize_metadata()
      |> Kernel.||(%{})

    normalized_usage =
      normalized_usage
      |> Map.put_new("input_tokens", value_or_zero(normalized_usage, :input_tokens))
      |> Map.put_new("output_tokens", value_or_zero(normalized_usage, :output_tokens))

    Map.put_new(
      normalized_usage,
      "total_tokens",
      Map.get(normalized_usage, "input_tokens", 0) + Map.get(normalized_usage, "output_tokens", 0)
    )
  end

  defp normalize_usage(_usage), do: nil

  defp value_or_zero(map, key) do
    case map_get(map, key) do
      value when is_number(value) -> value
      _other -> 0
    end
  end

  defp normalize_metadata(nil), do: nil
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_get(_map, _key, default), do: default

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, value) when value == "", do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp random_id(prefix) do
    "#{prefix}_" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
  end
end
