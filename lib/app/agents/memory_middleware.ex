defmodule App.Agents.MemoryMiddleware do
  @moduledoc """
  Alloy middleware for active memory recall and save prompting.

  On :before_completion, injects user and agent preferences/profile memories into the system prompt
  and appends instructions for the LLM to proactively use memory tools.
  """

  @behaviour Alloy.Middleware

  alias Alloy.Agent.State

  @memory_instruction """

  ## Memory
  You have internal tools to persist and recall information across conversations:
  - memory_set: Save facts, preferences, or notes about the user
  - memory_get: Retrieve stored memories by key, tags, or search
  - memory_update: Update existing memories

  Proactively use these tools when the user shares preferences, personal details, or important context worth remembering for future conversations.
  """

  @impl true
  def call(:before_completion, %State{} = state) do
    context = state.config.context
    agent_id = Map.get(context, :agent_id)

    opts = memory_scope_opts(context)

    user_memories = App.Agents.list_user_profile_memories_for_prompt(opts)

    agent_memories =
      if agent_id do
        App.Agents.list_memories_for_prompt(agent_id, opts)
      else
        []
      end

    org_memory_keys = App.Agents.list_org_memory_keys_for_prompt(opts)

    memories_block = format_memories_block(user_memories, agent_memories, org_memory_keys)

    current_prompt = state.config.system_prompt || ""

    new_prompt =
      current_prompt
      |> append_memories(memories_block)
      |> append_memory_instruction()

    if new_prompt == current_prompt do
      state
    else
      update_system_prompt(state, new_prompt)
    end
  end

  def call(_hook, %State{} = state), do: state

  defp memory_scope_opts(context) do
    [
      organization_id: Map.get(context, :organization_id),
      user_id: Map.get(context, :user_id)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp format_memories_block([], [], []), do: ""

  defp format_memories_block(user_memories, agent_memories, org_memory_keys) do
    user_block =
      if user_memories == [] do
        ""
      else
        "\n### User Profile & Preferences\n" <> memory_key_value_items(user_memories)
      end

    agent_block =
      if agent_memories == [] do
        ""
      else
        "\n### Agent Preferences\n" <> memory_key_value_items(agent_memories)
      end

    org_block =
      if org_memory_keys == [] do
        ""
      else
        "\n### Org Memory Index (keys only)\n" <>
          "Use `memory_get` with scope `org` when you need the value.\n" <>
          memory_key_items(org_memory_keys)
      end

    "\n\n## Known Memories\n#{user_block}#{agent_block}#{org_block}\n"
  end

  defp memory_key_value_items(memories) do
    Enum.map_join(memories, "\n", fn memory ->
      tags_label =
        case memory.tags do
          [] -> ""
          tags -> " [#{Enum.join(tags, ", ")}]"
        end

      "- **#{memory.key}**: #{memory.value}#{tags_label}"
    end)
  end

  defp memory_key_items(memories) do
    Enum.map_join(memories, "\n", fn memory ->
      tags_label =
        case memory.tags do
          [] -> ""
          tags -> " [#{Enum.join(tags, ", ")}]"
        end

      "- **#{memory.key}**#{tags_label}"
    end)
  end

  defp append_memories(prompt, ""), do: prompt
  defp append_memories(prompt, block), do: prompt <> block

  defp append_memory_instruction(prompt) do
    if String.contains?(prompt, "memory_set") do
      prompt
    else
      prompt <> @memory_instruction
    end
  end

  defp update_system_prompt(%State{} = state, new_prompt) do
    updated_config = %{state.config | system_prompt: new_prompt}
    %{state | config: updated_config}
  end
end
