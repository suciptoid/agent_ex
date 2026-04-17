defmodule App.Chat.Compaction do
  @moduledoc false

  require Logger

  alias App.Agents.Agent
  alias App.Providers.AlloyConfig
  alias App.Providers.Provider

  def generate_summary(agent, latest_checkpoint, messages, opts \\ [])

  def generate_summary(%Agent{} = agent, latest_checkpoint, messages, opts)
      when is_list(messages) and is_list(opts) do
    policy = Keyword.get(opts, :policy, %{})

    case llm_summary(agent, latest_checkpoint, messages, policy) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        Logger.warning(
          "[Compaction] Falling back to local checkpoint summary: #{inspect(reason)}"
        )

        {:ok, fallback_summary(latest_checkpoint, messages, policy)}
    end
  end

  defp llm_summary(
         %Agent{provider: %Provider{} = provider, model: model} = _agent,
         latest_checkpoint,
         messages,
         policy
       ) do
    max_tokens = Map.get(policy, :checkpoint_summary_max_tokens, 1_200)

    alloy_messages =
      maybe_existing_checkpoint_messages(latest_checkpoint) ++
        Enum.map(messages, &to_compaction_message(&1, policy)) ++
        [Alloy.Message.user(compaction_user_prompt())]

    alloy_provider = AlloyConfig.to_alloy_provider(provider, model)

    case Alloy.run(
           provider: alloy_provider,
           system_prompt: compaction_system_prompt(),
           messages: alloy_messages,
           max_turns: 1,
           max_tokens: max_tokens,
           tools: []
         ) do
      {:ok, %Alloy.Result{text: text}} ->
        case to_string(text) |> String.trim() do
          "" -> {:error, :empty_checkpoint_summary}
          summary -> {:ok, summary}
        end

      {:error, %Alloy.Result{error: error}} ->
        {:error, error}
    end
  end

  defp llm_summary(%Agent{}, _latest_checkpoint, _messages, _policy),
    do: {:error, :provider_not_preloaded}

  defp maybe_existing_checkpoint_messages(nil), do: []

  defp maybe_existing_checkpoint_messages(checkpoint) do
    summary =
      checkpoint
      |> Map.get(:content, Map.get(checkpoint, "content"))
      |> to_string()
      |> String.trim()

    if summary == "" do
      []
    else
      [
        Alloy.Message.user("Existing checkpoint summary of earlier conversation:\n\n" <> summary)
      ]
    end
  end

  defp to_compaction_message(message, policy) do
    role = Map.get(message, :role) || Map.get(message, "role")

    content =
      truncate_content(Map.get(message, :content) || Map.get(message, "content"), role, policy)

    name = Map.get(message, :name) || Map.get(message, "name")

    case role do
      "assistant" -> Alloy.Message.assistant(content || "")
      "tool" -> Alloy.Message.user("[Tool #{name || "tool"}] #{content || ""}")
      "system" -> Alloy.Message.user("[System context] #{content || ""}")
      "checkpoint" -> Alloy.Message.user("[Checkpoint] #{content || ""}")
      _other -> Alloy.Message.user(content || "")
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

  defp fallback_summary(latest_checkpoint, messages, policy) do
    max_chars =
      policy
      |> Map.get(:checkpoint_summary_max_tokens, 1_200)
      |> Kernel.*(4)
      |> max(800)

    sections =
      [
        fallback_existing_checkpoint_section(latest_checkpoint, max_chars),
        fallback_recent_messages_section(messages, policy)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))

    sections
    |> Enum.join("\n\n")
    |> truncate_to(max_chars)
  end

  defp fallback_existing_checkpoint_section(nil, _max_chars), do: nil

  defp fallback_existing_checkpoint_section(checkpoint, max_chars) do
    checkpoint
    |> Map.get(:content, Map.get(checkpoint, "content"))
    |> to_string()
    |> String.trim()
    |> case do
      "" ->
        nil

      summary ->
        "Earlier checkpoint summary:\n" <> truncate_to(summary, div(max_chars, 2))
    end
  end

  defp fallback_recent_messages_section(messages, policy) do
    lines =
      messages
      |> Enum.map(&fallback_summary_line(&1, policy))
      |> Enum.reject(&(&1 == ""))

    case lines do
      [] -> "Recent summarized messages:\n- No earlier messages were available."
      _other -> "Recent summarized messages:\n" <> Enum.join(lines, "\n")
    end
  end

  defp fallback_summary_line(message, policy) do
    role = Map.get(message, :role) || Map.get(message, "role") || "message"
    name = Map.get(message, :name) || Map.get(message, "name")
    tool_call_id = Map.get(message, :tool_call_id) || Map.get(message, "tool_call_id")

    content =
      message
      |> Map.get(:content, Map.get(message, "content"))
      |> truncate_content(role, policy)
      |> squash_whitespace()

    case role do
      "tool" ->
        label =
          [name || "tool", tool_call_id]
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(" ")

        "- tool #{label}: #{blank_to_placeholder(content)}"

      _other ->
        "- #{role}: #{blank_to_placeholder(content)}"
    end
  end

  defp squash_whitespace(value) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp squash_whitespace(value), do: value

  defp blank_to_placeholder(""), do: "[no content]"
  defp blank_to_placeholder(value), do: value

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
