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

  def run_streaming(%Agent{provider: %Provider{api_key: api_key}} = agent, messages, lv_pid, opts) do
    context = build_context(agent, messages, opts)
    tools = App.Agents.Tools.resolve(agent.tools) ++ Keyword.get(opts, :extra_tools, [])

    llm_opts =
      [api_key: api_key, tools: tools]
      |> merge_extra_params(agent.extra_params)
      |> Keyword.merge(Keyword.drop(opts, [:extra_tools, :extra_system_prompt]))

    Logger.debug("[Runner] Streaming agent #{agent.name}, tools: #{inspect(agent.tools)}")

    if Enum.empty?(tools) do
      stream_tokens(agent.model, context, llm_opts, lv_pid)
    else
      # Tool loop requires generate_text; emit result as single chunk when done
      case run_with_tool_loop(agent.model, context, tools, llm_opts) do
        {:ok, response} ->
          content = ReqLLM.Response.text(response) || "The agent returned an empty response."
          send(lv_pid, {:stream_chunk, content})
          usage = normalize_metadata(ReqLLM.Response.usage(response))
          {:ok, %{content: content, usage: usage}}

        {:error, reason} ->
          {:error, reason}
      end
    end
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

  defp stream_tokens(model, context, llm_opts, lv_pid) do
    case ReqLLM.stream_text(model, context, llm_opts) do
      {:ok, stream_response} ->
        full_text =
          stream_response
          |> ReqLLM.StreamResponse.tokens()
          |> Enum.reduce("", fn token, acc ->
            send(lv_pid, {:stream_chunk, token})
            acc <> token
          end)

        usage = normalize_metadata(ReqLLM.StreamResponse.usage(stream_response))
        Logger.debug("[Runner] Stream complete, length: #{String.length(full_text)}")
        {:ok, %{content: full_text, usage: usage}}

      {:error, reason} ->
        Logger.error("[Runner] Stream failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp normalize_metadata(nil), do: nil
  defp normalize_metadata(value), do: value |> Jason.encode!() |> Jason.decode!()
end
