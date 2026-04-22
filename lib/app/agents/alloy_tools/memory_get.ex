defmodule App.Agents.AlloyTools.MemoryGet do
  @moduledoc false
  @behaviour Alloy.Tool

  @impl true
  def name, do: "memory_get"

  @impl true
  def description,
    do:
      "Retrieve stored memories. Look up a specific memory by key, or search memories by tags. Returns matching memories with their values and metadata."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        key: %{
          type: "string",
          description: "Exact key to look up (optional if using tags)"
        },
        tags: %{
          type: "array",
          description: "Search for memories containing any of these tags",
          items: %{type: "string"}
        },
        scope: %{
          type: "string",
          description: "Filter by scope: 'org' or 'user'",
          enum: ["org", "user"]
        },
        query: %{
          type: "string",
          description: "Free-text search across memory keys and values"
        }
      }
    }
  end

  @impl true
  def execute(input, context) do
    agent_id = Map.get(context, :agent_id) || Map.get(context, "agent_id")
    key = Map.get(input, :key) || Map.get(input, "key")
    tags = Map.get(input, :tags) || Map.get(input, "tags")
    scope = Map.get(input, :scope) || Map.get(input, "scope")
    query = Map.get(input, :query) || Map.get(input, "query")

    opts =
      [
        organization_id:
          Map.get(context, :organization_id) || Map.get(context, "organization_id"),
        user_id: Map.get(context, :user_id) || Map.get(context, "user_id")
      ]
      |> maybe_put_opt(:scope, scope)

    cond do
      is_binary(key) and is_binary(scope) ->
        case App.Agents.get_memory(scope, agent_id, key, opts) do
          %App.Agents.Memory{} = memory ->
            {:ok, format_memory(memory)}

          nil ->
            {:ok, "No memory found with key '#{key}' in scope '#{scope}'"}
        end

      is_list(tags) and tags != [] ->
        memories = App.Agents.get_memories_by_tags(agent_id, tags, opts)
        {:ok, format_memories(memories, tags)}

      is_binary(query) ->
        memories = App.Agents.search_memories(agent_id, query, opts)
        {:ok, format_search_results(memories, query)}

      true ->
        {:error,
         "Provide at least one of: 'key' (with 'scope'), 'tags', or 'query' to search memories"}
    end
  end

  defp format_memory(memory) do
    "Memory: #{memory.key}\nValue: #{memory.value}\nScope: #{memory.scope}\nTags: #{Enum.join(memory.tags, ", ")}"
  end

  defp format_memories([], tags) do
    "No memories found with tags: #{Enum.join(tags, ", ")}"
  end

  defp format_memories(memories, _tags) do
    items =
      Enum.map(memories, fn memory ->
        "- #{memory.key}: #{memory.value} [scope: #{memory.scope}, tags: #{Enum.join(memory.tags, ", ")}]"
      end)
      |> Enum.join("\n")

    "Found #{length(memories)} memory(ies):\n#{items}"
  end

  defp format_search_results([], query) do
    "No memories matching '#{query}'"
  end

  defp format_search_results(memories, _query) do
    items =
      Enum.map(memories, fn memory ->
        "- #{memory.key}: #{memory.value} [scope: #{memory.scope}, tags: #{Enum.join(memory.tags, ", ")}]"
      end)
      |> Enum.join("\n")

    "Found #{length(memories)} memory(ies):\n#{items}"
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
