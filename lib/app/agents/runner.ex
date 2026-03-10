defmodule App.Agents.Runner do
  @moduledoc """
  Executes an agent against a conversation context using ReqLLM.
  """

  require Logger

  alias App.Agents.Agent
  alias App.Chat.Message
  alias App.Providers.Provider

  @default_system_prompt "You are a helpful assistant."
  @max_tool_iterations 5
  @supported_extra_params %{
    "temperature" => :temperature,
    "max_tokens" => :max_tokens
  }

  def run(agent, messages, opts \\ [])

  def run(%Agent{provider: %Provider{api_key: api_key}} = agent, messages, opts) do
    context = build_context(agent, messages, opts)
    tools = App.Agents.Tools.resolve(agent.tools) ++ Keyword.get(opts, :extra_tools, [])

    llm_opts =
      [api_key: api_key, tools: tools]
      |> merge_extra_params(agent.extra_params)
      |> Keyword.merge(Keyword.drop(opts, [:extra_tools, :extra_system_prompt]))

    Logger.debug(
      "[Runner] Running agent #{agent.name} with model #{agent.model}, #{length(messages)} messages"
    )

    case Keyword.get(llm_opts, :stream, false) do
      true ->
        ReqLLM.stream_text(agent.model, context, Keyword.delete(llm_opts, :stream))

      false ->
        run_with_tool_loop(agent.model, context, tools, llm_opts)
    end
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
    tools = App.Agents.Tools.resolve(agent.tools) ++ Keyword.get(opts, :extra_tools, [])

    llm_opts =
      [api_key: api_key, tools: tools]
      |> merge_extra_params(agent.extra_params)
      |> Keyword.merge(Keyword.drop(opts, [:extra_tools, :extra_system_prompt]))

    Logger.debug("[Runner] Streaming agent #{agent.name}, tools: #{inspect(agent.tools)}")
    on_result = build_stream_callback(recipient, opts)

    run_streaming_with_tool_loop(agent.model, context, tools, llm_opts, on_result)
  end

  def run_streaming(%Agent{}, _messages, _lv_pid, _opts),
    do: {:error, "agent provider must be preloaded"}

  defp run_with_tool_loop(model, context, tools, llm_opts, iteration \\ 0) do
    if iteration >= @max_tool_iterations do
      Logger.warning("[Runner] Max tool iterations (#{@max_tool_iterations}) reached")
      {:error, "Maximum tool call iterations reached (#{@max_tool_iterations})"}
    else
      case ReqLLM.generate_text(model, context, llm_opts) do
        {:ok, response} ->
          case ReqLLM.Response.classify(response) do
            %{type: :tool_calls, tool_calls: tool_calls} ->
              names = Enum.map(tool_calls, & &1.name)

              Logger.info(
                "[Runner] LLM requested tools (iteration #{iteration + 1}): #{inspect(names)}"
              )

              {:ok, tool_messages} = App.Agents.Tools.execute_all(tool_calls, tools)

              new_context =
                response.context
                |> ReqLLM.Context.append(response.message)
                |> ReqLLM.Context.append(tool_messages)

              run_with_tool_loop(model, new_context, tools, llm_opts, iteration + 1)

            %{type: :final_answer} ->
              text = ReqLLM.Response.text(response)
              Logger.debug("[Runner] Final answer received, length: #{String.length(text || "")}")
              {:ok, response}
          end

        {:error, reason} ->
          Logger.error("[Runner] LLM call failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
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
        Enum.map(messages, &to_req_llm_message/1)

    ReqLLM.Context.new(messages)
  end

  defp to_req_llm_message(%Message{role: role, content: content}) do
    req_llm_message(role, content)
  end

  defp to_req_llm_message(%{role: role, content: content}) do
    req_llm_message(role, content)
  end

  defp req_llm_message("assistant", content), do: ReqLLM.Context.assistant(content || "")
  defp req_llm_message("system", content), do: ReqLLM.Context.system(content || "")
  defp req_llm_message(_role, content), do: ReqLLM.Context.user(content || "")

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

  defp run_streaming_with_tool_loop(
         model,
         context,
         tools,
         llm_opts,
         on_result,
         iteration \\ 0,
         accumulated_text \\ "",
         accumulated_usage \\ nil
       ) do
    if iteration >= @max_tool_iterations do
      Logger.warning("[Runner] Max tool iterations (#{@max_tool_iterations}) reached")
      {:error, "Maximum tool call iterations reached (#{@max_tool_iterations})"}
    else
      with {:ok, response} <- stream_response(model, context, llm_opts, on_result) do
        %{type: type, text: text, tool_calls: tool_calls} = ReqLLM.Response.classify(response)
        usage = normalize_metadata(ReqLLM.Response.usage(response))
        accumulated_text = accumulated_text <> (text || "")
        accumulated_usage = merge_usage_maps(accumulated_usage, usage)

        case {type, tool_calls} do
          {:tool_calls, []} ->
            Logger.error("[Runner] Stream finished with tool_calls but no tool payload")
            {:error, "The model requested a tool call without any tool data"}

          {:tool_calls, tool_calls} ->
            names = Enum.map(tool_calls, & &1.name)

            Logger.info(
              "[Runner] Stream requested tools (iteration #{iteration + 1}): #{inspect(names)}"
            )

            with {:ok, tool_messages} <- App.Agents.Tools.execute_all(tool_calls, tools) do
              new_context =
                response.context
                |> ReqLLM.Context.append(response.message)
                |> ReqLLM.Context.append(tool_messages)

              run_streaming_with_tool_loop(
                model,
                new_context,
                tools,
                llm_opts,
                on_result,
                iteration + 1,
                accumulated_text,
                accumulated_usage
              )
            end

          {:final_answer, _tool_calls} ->
            final_content =
              if blank?(accumulated_text),
                do: "The agent returned an empty response.",
                else: accumulated_text

            Logger.debug(
              "[Runner] Streaming final answer complete, length: #{String.length(final_content)}"
            )

            {:ok, %{content: final_content, usage: accumulated_usage}}
        end
      end
    end
  end

  defp stream_response(model, context, llm_opts, on_result) do
    case ReqLLM.stream_text(model, context, llm_opts) do
      {:ok, stream_response} ->
        ReqLLM.StreamResponse.process_stream(stream_response, on_result: on_result)

      {:error, reason} ->
        Logger.error("[Runner] Stream failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_stream_callback(recipient, opts) do
    case Keyword.get(opts, :on_result) do
      callback when is_function(callback, 1) ->
        callback

      _ when is_pid(recipient) ->
        fn token -> send(recipient, {:stream_chunk, token}) end

      _ ->
        fn _token -> :ok end
    end
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
end
