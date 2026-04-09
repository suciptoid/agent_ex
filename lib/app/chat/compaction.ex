defmodule App.Chat.Compaction do
  @moduledoc false

  alias App.Agents.Agent
  alias App.Providers.Provider

  def generate_summary(agent, latest_checkpoint, messages, opts \\ [])

  def generate_summary(
        %Agent{provider: %Provider{api_key: api_key}} = agent,
        latest_checkpoint,
        messages,
        opts
      )
      when is_list(messages) and is_list(opts) do
    policy = Keyword.get(opts, :policy, %{})
    max_tokens = Map.get(policy, :checkpoint_summary_max_tokens, 1_200)

    context =
      ReqLLM.Context.new(
        [
          ReqLLM.Context.system(compaction_system_prompt())
        ] ++
          maybe_existing_checkpoint(latest_checkpoint) ++
          Enum.map(messages, &to_compaction_message(&1, policy)) ++
          [ReqLLM.Context.user(compaction_user_prompt())]
      )

    case ReqLLM.generate_text(agent.model, context,
           api_key: api_key,
           temperature: 0,
           max_tokens: max_tokens
         ) do
      {:ok, response} ->
        case response |> ReqLLM.Response.text() |> to_string() |> String.trim() do
          "" -> {:error, :empty_checkpoint_summary}
          summary -> {:ok, summary}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def generate_summary(%Agent{}, _latest_checkpoint, _messages, _opts),
    do: {:error, "agent provider must be preloaded"}

  defp maybe_existing_checkpoint(nil), do: []

  defp maybe_existing_checkpoint(checkpoint) do
    summary =
      checkpoint
      |> Map.get(:content, Map.get(checkpoint, "content"))
      |> to_string()
      |> String.trim()

    if summary == "" do
      []
    else
      [
        ReqLLM.Context.system(
          "Existing checkpoint summary of earlier conversation:\n\n" <> summary
        )
      ]
    end
  end

  defp to_compaction_message(message, policy) do
    role = Map.get(message, :role) || Map.get(message, "role")

    content =
      truncate_content(Map.get(message, :content) || Map.get(message, "content"), role, policy)

    name = Map.get(message, :name) || Map.get(message, "name")
    tool_call_id = Map.get(message, :tool_call_id) || Map.get(message, "tool_call_id")
    tool_calls = Map.get(message, :tool_calls, Map.get(message, "tool_calls", [])) |> List.wrap()

    case role do
      "assistant" -> ReqLLM.Context.assistant(content || "", tool_calls: tool_calls)
      "system" -> ReqLLM.Context.system(content || "")
      "tool" -> ReqLLM.Context.tool_result(tool_call_id || "", name || "tool", content || "")
      "checkpoint" -> ReqLLM.Context.system(content || "")
      _other -> ReqLLM.Context.user(content || "")
    end
  end

  defp truncate_content(nil, _role, _policy), do: ""

  defp truncate_content(content, "tool", policy) do
    content
    |> to_string()
    |> truncate_to(Map.get(policy, :compaction_tool_chars, 600))
  end

  defp truncate_content(content, _role, policy) do
    content
    |> to_string()
    |> truncate_to(Map.get(policy, :compaction_message_chars, 4_000))
  end

  defp truncate_to(content, limit) when is_binary(content) do
    if String.length(content) <= limit do
      content
    else
      String.slice(content, 0, limit) <> "..."
    end
  end

  defp compaction_system_prompt do
    """
    You are compressing older chat history into a durable checkpoint.

    Produce a concise but information-dense summary that preserves:
    - the user's goals
    - important constraints or instructions
    - key discoveries and decisions
    - work already completed
    - unresolved follow-ups
    - notable tools, APIs, files, or entities that still matter

    Do not call tools. Do not narrate that you are summarizing.
    """
    |> String.trim()
  end

  defp compaction_user_prompt do
    """
    Write the checkpoint summary for the conversation above. Keep it compact, structured, and directly useful for continuing the task later.
    """
    |> String.trim()
  end
end
