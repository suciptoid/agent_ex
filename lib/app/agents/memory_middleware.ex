defmodule App.Agents.MemoryMiddleware do
  @moduledoc """
  Alloy middleware for active memory recall and save prompting.

  On :before_completion, injects preference/profile memories into the system prompt
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

    memories_block =
      if agent_id do
        opts = memory_scope_opts(context)
        memories = App.Agents.list_memories_for_prompt(agent_id, opts)
        format_memories_block(memories)
      else
        ""
      end

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

  defp format_memories_block([]), do: ""

  defp format_memories_block(memories) do
    items =
      Enum.map(memories, fn memory ->
        tags_label =
          case memory.tags do
            [] -> ""
            tags -> " [#{Enum.join(tags, ", ")}]"
          end

        "- **#{memory.key}**: #{memory.value}#{tags_label}"
      end)
      |> Enum.join("\n")

    "\n\n## Known Memories\nThe following information was previously stored and should inform your responses:\n\n#{items}\n"
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
