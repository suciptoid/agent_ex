defmodule App.Agents.Runner do
  @moduledoc """
  Executes an agent against a conversation context using ReqLLM.
  """

  require Logger

  alias App.Agents.Agent
  alias App.Agents.Runner.DoomLoop
  alias App.Chat.ContextBuilder
  alias App.Chat.Message
  alias App.Providers.Provider

  @default_system_prompt "You are a helpful assistant."
  @supported_extra_params %{
    "temperature" => :temperature,
    "max_tokens" => :max_tokens
  }

  def run(agent, messages, opts \\ [])

  def run(%Agent{provider: %Provider{api_key: api_key}} = agent, messages, opts) do
    context = build_context(agent, messages, opts)

    tools =
      App.Agents.Tools.resolve(agent.tools, organization_id: agent.organization_id) ++
        Keyword.get(opts, :extra_tools, [])

    llm_opts =
      [api_key: api_key, tools: tools]
      |> merge_extra_params(agent.extra_params)
      |> Keyword.merge(keyword_stream_opts(opts))

    Logger.debug(
      "[Runner] Running agent #{agent.name} with model #{agent.model}, #{length(messages)} messages"
    )

    run_with_tool_loop(agent.model, context, tools, llm_opts, noop_callbacks())
  end

  def run(%Agent{}, _messages, _opts), do: {:error, "agent provider must be preloaded"}

  def run_streaming(agent, messages, lv_pid, opts \\ [])

  def run_streaming(
        %Agent{provider: %Provider{api_key: api_key}} = agent,
        messages,
        recipient,
        opts
      ) do
    context = build_context(agent, messages, opts)

    tools =
      App.Agents.Tools.resolve(agent.tools, organization_id: agent.organization_id) ++
        Keyword.get(opts, :extra_tools, [])

    llm_opts =
      [api_key: api_key, tools: tools]
      |> merge_extra_params(agent.extra_params)
      |> Keyword.merge(keyword_stream_opts(opts))

    Logger.debug("[Runner] Streaming agent #{agent.name}, tools: #{inspect(agent.tools)}")
    callbacks = build_stream_callbacks(recipient, opts)

    run_with_tool_loop(agent.model, context, tools, llm_opts, callbacks)
  end

  def run_streaming(%Agent{}, _messages, _lv_pid, _opts),
    do: {:error, "agent provider must be preloaded"}

  defp run_with_tool_loop(
         model,
         context,
         tools,
         llm_opts,
         callbacks,
         result_state \\ initial_result_state()
       ) do
    case stream_response(model, context, llm_opts, callbacks) do
      {:ok, response} ->
        %{
          type: type,
          text: text,
          thinking: thinking,
          tool_calls: tool_calls,
          finish_reason: finish_reason
        } =
          ReqLLM.Response.classify(response)

        usage = normalize_metadata(ReqLLM.Response.usage(response))
        provider_meta = normalize_metadata(response.provider_meta)

        base_result_state =
          result_state
          |> merge_usage(usage)
          |> put_provider_meta(provider_meta)
          |> put_finish_reason(finish_reason)

        case {type, tool_calls} do
          {:tool_calls, []} ->
            Logger.error("[Runner] Stream finished with tool_calls but no tool payload")
            {:error, "The model requested a tool call without any tool data"}

          {:tool_calls, tool_calls} ->
            names = Enum.map(tool_calls, & &1.name)
            tool_call_turn = build_tool_call_turn(text, thinking, tool_calls)

            Logger.info("[Runner] LLM requested tools: #{inspect(names)}")
            callbacks.on_tool_calls.(tool_call_turn)

            case DoomLoop.detect(result_state.tool_call_turns, tool_calls) do
              {:doom_loop, %{name: tool_name, arguments: arguments}} ->
                Logger.warning(
                  "[Runner] Tool doom loop detected for #{inspect(tool_name)} with arguments #{inspect(arguments)}"
                )

                {:error, doom_loop_error(tool_name)}

              :ok ->
                with {:ok, %{messages: tool_messages, results: tool_results}} <-
                       App.Agents.Tools.execute_all(tool_calls, tools,
                         on_tool_start: callbacks.on_tool_start
                       ) do
                  Enum.each(tool_results, callbacks.on_tool_result)

                  new_context =
                    response.context
                    |> ReqLLM.Context.append(response.message)
                    |> ReqLLM.Context.append(tool_messages)

                  run_with_tool_loop(
                    model,
                    new_context,
                    tools,
                    llm_opts,
                    callbacks,
                    base_result_state
                    |> append_tool_call_turn(tool_call_turn)
                    |> append_tool_responses(tool_results)
                  )
                end
            end

          {:final_answer, _tool_calls} ->
            final_result_state =
              base_result_state
              |> append_text(text)
              |> append_thinking(thinking)

            final_content =
              if blank?(final_result_state.content),
                do: "The agent returned an empty response.",
                else: final_result_state.content

            Logger.debug(
              "[Runner] Final answer received, length: #{String.length(final_content)}"
            )

            {:ok, %{final_result_state | content: final_content}}
        end

      {:error, reason} ->
        Logger.error("[Runner] LLM call failed: #{error_text(reason)}")
        {:error, reason}
    end
  end

  defp doom_loop_error(nil),
    do: "Detected repeated identical tool calls. Stopping to avoid a doom loop."

  defp doom_loop_error(tool_name) do
    "Detected repeated #{inspect(tool_name)} tool calls with identical arguments. Stopping to avoid a doom loop."
  end

  defp build_context(agent, messages, opts) do
    base_system_prompt =
      if blank?(agent.system_prompt), do: @default_system_prompt, else: agent.system_prompt

    extra_system_prompt = Keyword.get(opts, :extra_system_prompt, "")

    system_prompt =
      if blank?(extra_system_prompt) do
        base_system_prompt
      else
        base_system_prompt <> "\n\n" <> extra_system_prompt
      end

    messages =
      [ReqLLM.Context.system(system_prompt)] ++
        (messages
         |> ContextBuilder.canonical_messages()
         |> Enum.map(&to_req_llm_message/1))

    ReqLLM.Context.new(messages)
  end

  defp to_req_llm_message(%Message{role: role, content: content} = message) do
    req_llm_message(role, content,
      name: message.name,
      tool_call_id: message.tool_call_id,
      tool_calls: Message.tool_calls(message),
      metadata: message.metadata || %{}
    )
  end

  defp to_req_llm_message(%{role: role} = message) do
    req_llm_message(role, message_content(message),
      name: Map.get(message, :name) || Map.get(message, "name"),
      tool_call_id: Map.get(message, :tool_call_id) || Map.get(message, "tool_call_id"),
      tool_calls: message_tool_calls(message),
      metadata: Map.get(message, :metadata) || Map.get(message, "metadata") || %{}
    )
  end

  defp req_llm_message("assistant", content, opts) do
    case Keyword.get(opts, :tool_calls, []) do
      [] -> ReqLLM.Context.assistant(content || "")
      tool_calls -> ReqLLM.Context.assistant(content || "", tool_calls: tool_calls)
    end
  end

  defp req_llm_message("system", content, _opts), do: ReqLLM.Context.system(content || "")
  defp req_llm_message("checkpoint", content, _opts), do: ReqLLM.Context.system(content || "")

  defp req_llm_message("tool", content, opts) do
    tool_call_id = Keyword.get(opts, :tool_call_id) || ""

    case Keyword.get(opts, :name) do
      nil -> ReqLLM.Context.tool_result(tool_call_id, content || "")
      name -> ReqLLM.Context.tool_result(tool_call_id, name, content || "")
    end
  end

  defp req_llm_message(_role, content, _opts), do: ReqLLM.Context.user(content || "")

  defp merge_extra_params(opts, nil), do: opts
  defp merge_extra_params(opts, extra_params) when extra_params == %{}, do: opts

  defp merge_extra_params(opts, extra_params) do
    Enum.reduce(extra_params, opts, fn {key, value}, acc ->
      case Map.get(@supported_extra_params, to_string(key)) do
        nil -> acc
        option_key -> Keyword.put(acc, option_key, value)
      end
    end)
  end

  defp blank?(value), do: value in [nil, ""]
  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp stream_response(model, context, llm_opts, callbacks) do
    case ReqLLM.stream_text(model, context, llm_opts) do
      {:ok, stream_response} ->
        ReqLLM.StreamResponse.process_stream(
          stream_response,
          on_result: callbacks.on_result,
          on_thinking: callbacks.on_thinking
        )

      {:error, reason} ->
        Logger.error("[Runner] Stream failed: #{error_text(reason)}")
        {:error, reason}
    end
  end

  defp error_text({:error, reason}), do: error_text(reason)
  defp error_text({reason, _stacktrace}), do: error_text(reason)
  defp error_text(%{reason: reason}) when not is_nil(reason), do: error_text(reason)
  defp error_text(%{"reason" => reason}) when not is_nil(reason), do: error_text(reason)
  defp error_text(%{response_body: %{"message" => message}}) when is_binary(message), do: message

  defp error_text(%{"response_body" => %{"message" => message}}) when is_binary(message),
    do: message

  defp error_text(%{message: message}) when is_binary(message), do: message
  defp error_text(%{"message" => message}) when is_binary(message), do: message
  defp error_text(%{__exception__: true} = exception), do: Exception.message(exception)
  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason) when is_atom(reason), do: Phoenix.Naming.humanize(to_string(reason))
  defp error_text(reason), do: inspect(reason)

  defp build_stream_callbacks(recipient, opts) do
    %{
      on_result:
        resolve_callback(
          Keyword.get(opts, :on_result),
          recipient,
          fn token -> {:stream_chunk, token} end
        ),
      on_thinking:
        resolve_callback(
          Keyword.get(opts, :on_thinking),
          recipient,
          fn token -> {:stream_thinking_chunk, token} end
        ),
      on_tool_result:
        resolve_callback(
          Keyword.get(opts, :on_tool_result),
          recipient,
          fn tool_result -> {:stream_tool_result, tool_result} end
        ),
      on_tool_calls:
        resolve_callback(
          Keyword.get(opts, :on_tool_calls),
          recipient,
          fn tool_call_turn -> {:stream_tool_calls, tool_call_turn} end
        ),
      on_tool_start:
        resolve_callback(
          Keyword.get(opts, :on_tool_start),
          recipient,
          fn tool_result -> {:stream_tool_started, tool_result} end
        )
    }
  end

  defp noop_callbacks do
    %{
      on_result: fn _token -> :ok end,
      on_thinking: fn _token -> :ok end,
      on_tool_calls: fn _tool_call_turn -> :ok end,
      on_tool_start: fn _tool_result -> :ok end,
      on_tool_result: fn _tool_result -> :ok end
    }
  end

  defp resolve_callback(callback, _recipient, _message_builder) when is_function(callback, 1),
    do: callback

  defp resolve_callback(_callback, recipient, message_builder) when is_pid(recipient) do
    fn payload -> send(recipient, message_builder.(payload)) end
  end

  defp resolve_callback(_callback, _recipient, _message_builder), do: fn _payload -> :ok end

  defp keyword_stream_opts(opts) do
    Keyword.drop(opts, [
      :extra_tools,
      :extra_system_prompt,
      :on_result,
      :on_thinking,
      :on_tool_calls,
      :on_tool_start,
      :on_tool_result
    ])
  end

  defp initial_result_state do
    %{
      content: "",
      thinking: "",
      tool_call_turns: [],
      tool_responses: [],
      usage: nil,
      finish_reason: nil,
      provider_meta: %{}
    }
  end

  defp append_text(result_state, text) when text in [nil, ""], do: result_state

  defp append_text(result_state, text),
    do: %{result_state | content: result_state.content <> text}

  defp append_thinking(result_state, thinking) when thinking in [nil, ""], do: result_state

  defp append_thinking(result_state, thinking) do
    %{result_state | thinking: result_state.thinking <> thinking}
  end

  defp append_tool_responses(result_state, []), do: result_state

  defp append_tool_responses(result_state, tool_responses) do
    %{result_state | tool_responses: result_state.tool_responses ++ tool_responses}
  end

  defp append_tool_call_turn(result_state, tool_call_turn) do
    %{result_state | tool_call_turns: result_state.tool_call_turns ++ [tool_call_turn]}
  end

  defp merge_usage(result_state, usage) do
    %{result_state | usage: merge_usage_maps(result_state.usage, usage)}
  end

  defp put_provider_meta(result_state, nil), do: result_state

  defp put_provider_meta(result_state, provider_meta),
    do: %{result_state | provider_meta: provider_meta}

  defp put_finish_reason(result_state, nil), do: result_state

  defp put_finish_reason(result_state, finish_reason) do
    %{result_state | finish_reason: to_string(finish_reason)}
  end

  defp merge_usage_maps(nil, nil), do: nil
  defp merge_usage_maps(nil, usage), do: usage
  defp merge_usage_maps(usage, nil), do: usage

  defp merge_usage_maps(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_number(left_value) and is_number(right_value) do
        left_value + right_value
      else
        right_value
      end
    end)
  end

  defp normalize_metadata(nil), do: nil
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp build_tool_call_turn(text, thinking, tool_calls) do
    %{}
    |> maybe_put_map_value("content", blank_to_nil(text))
    |> maybe_put_map_value("thinking", blank_to_nil(thinking))
    |> Map.put("tool_calls", normalize_metadata(tool_calls) || [])
  end

  defp message_tool_calls(%{} = message) do
    message
    |> Map.get(:tool_calls, Map.get(message, "tool_calls", []))
    |> List.wrap()
  end

  defp message_content(%{} = message),
    do: Map.get(message, :content) || Map.get(message, "content")

  defp maybe_put_map_value(map, _key, nil), do: map
  defp maybe_put_map_value(map, key, value), do: Map.put(map, key, value)
end
