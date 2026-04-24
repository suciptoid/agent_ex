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
          description: "Filter by ownership: 'org', 'user', or 'agent'",
          enum: ["org", "user", "agent"]
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
    key = normalize_optional_text(Map.get(input, :key) || Map.get(input, "key"))
    tags = normalize_tags(Map.get(input, :tags) || Map.get(input, "tags"))
    scope = normalize_optional_text(Map.get(input, :scope) || Map.get(input, "scope"))
    query = normalize_optional_text(Map.get(input, :query) || Map.get(input, "query"))

    opts =
      [
        organization_id:
          Map.get(context, :organization_id) || Map.get(context, "organization_id"),
        user_id: Map.get(context, :user_id) || Map.get(context, "user_id"),
        agent_id: agent_id
      ]
      |> maybe_put_opt(:scope, scope)

    cond do
      is_binary(scope) and is_binary(key) ->
        case App.Agents.get_memory(scope, key, opts) do
          %App.Agents.Memory{} = memory ->
            {:ok, format_memory(memory)}

          nil ->
            {:ok, "No memory found with key '#{key}' in ownership '#{scope}'"}
        end

      is_list(tags) and tags != [] ->
        memories = App.Agents.get_memories_by_tags(tags, opts)
        {:ok, format_memories(memories, tags)}

      is_binary(query) ->
        memories = App.Agents.search_memories(query, opts)
        {:ok, format_search_results(memories, query)}

      is_binary(scope) and is_nil(key) ->
        {:error, "Provide a non-blank key, tags, or query"}

      true ->
        {:error, "Provide a non-blank key, tags, or query to search memories"}
    end
  end

  defp format_memory(memory) do
    "Memory: #{memory.key}\nValue: #{memory.value}\nOwnership: #{App.Agents.Memory.ownership(memory)}\nTags: #{Enum.join(memory.tags, ", ")}"
  end

  defp format_memories([], tags) do
    "No memories found with tags: #{Enum.join(tags, ", ")}"
  end

  defp format_memories(memories, _tags) do
    items =
      Enum.map(memories, fn memory ->
        "- #{memory.key}: #{memory.value} [ownership: #{App.Agents.Memory.ownership(memory)}, tags: #{Enum.join(memory.tags, ", ")}]"
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
        "- #{memory.key}: #{memory.value} [ownership: #{App.Agents.Memory.ownership(memory)}, tags: #{Enum.join(memory.tags, ", ")}]"
      end)
      |> Enum.join("\n")

    "Found #{length(memories)} memory(ies):\n#{items}"
  end

  defp maybe_put_opt(opts, _key, nil), do: opts
  defp maybe_put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(value), do: value

  defp normalize_tags(tags) do
    tags
    |> List.wrap()
    |> Enum.map(&normalize_optional_text/1)
    |> Enum.reject(&is_nil/1)
  end
end
