defmodule App.Agents.Runner do
  @moduledoc """
  Executes an agent against a conversation context using ReqLLM.
  """

  alias App.Agents.Agent
  alias App.Chat.Message
  alias App.Providers.Provider

  @default_system_prompt "You are a helpful assistant."
  @supported_extra_params %{
    "temperature" => :temperature,
    "max_tokens" => :max_tokens
  }

  def run(agent, messages, opts \\ [])

  def run(%Agent{provider: %Provider{api_key: api_key}} = agent, messages, opts) do
    context = build_context(agent, messages)

    llm_opts =
      [api_key: api_key, tools: App.Agents.Tools.resolve(agent.tools)]
      |> merge_extra_params(agent.extra_params)
      |> Keyword.merge(opts)

    case Keyword.get(llm_opts, :stream, false) do
      true ->
        ReqLLM.stream_text(agent.model, context, Keyword.delete(llm_opts, :stream))

      false ->
        ReqLLM.generate_text(agent.model, context, llm_opts)
    end
  end

  def run(%Agent{}, _messages, _opts), do: {:error, "agent provider must be preloaded"}

  defp build_context(agent, messages) do
    system_prompt =
      if blank?(agent.system_prompt), do: @default_system_prompt, else: agent.system_prompt

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
end
