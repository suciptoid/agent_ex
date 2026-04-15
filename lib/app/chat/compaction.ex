defmodule App.Chat.Compaction do
  @moduledoc false

  require Logger

  alias App.Agents.Agent
  alias App.LLM.Client
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
         %Agent{provider: %Provider{}} = agent,
         latest_checkpoint,
         messages,
         policy
       ) do
    max_tokens = Map.get(policy, :checkpoint_summary_max_tokens, 1_200)

    messages =
      maybe_existing_checkpoint(latest_checkpoint) ++
        Enum.map(messages, &to_compaction_message(&1, policy)) ++
        [%{role: "user", content: compaction_user_prompt()}]

    Client.generate_text(agent.provider, agent.model, messages,
      system_prompt: compaction_system_prompt(),
      temperature: 0,
      max_tokens: max_tokens
    )
  end

  defp llm_summary(%Agent{}, _latest_checkpoint, _messages, _policy),
    do: {:error, :provider_not_preloaded}

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
        %{
          role: "system",
          content: "Existing checkpoint summary of earlier conversation:\n\n" <> summary
        }
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

    %{}
    |> Map.put(:role, normalize_role(role))
    |> Map.put(:content, content || "")
    |> maybe_put(:name, name)
    |> maybe_put(:tool_call_id, tool_call_id)
    |> maybe_put(:tool_calls, tool_calls)
  end

  defp normalize_role("assistant"), do: "assistant"
  defp normalize_role("system"), do: "system"
  defp normalize_role("tool"), do: "tool"
  defp normalize_role("checkpoint"), do: "checkpoint"
  defp normalize_role(_role), do: "user"

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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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
