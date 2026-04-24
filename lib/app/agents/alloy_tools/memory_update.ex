defmodule App.Agents.AlloyTools.MemoryUpdate do
  @moduledoc false
  @behaviour Alloy.Tool

  @impl true
  def name, do: "memory_update"

  @impl true
  def description,
    do:
      "Update an existing memory's value and/or tags. The memory must already exist (use memory_set to create new memories)."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        key: %{
          type: "string",
          description: "The key of the memory to update"
        },
        value: %{
          type: "string",
          description: "New value for the memory"
        },
        tags: %{
          type: "array",
          description: "Replace the memory's tags with this list",
          items: %{type: "string"}
        },
        scope: %{
          type: "string",
          description:
            "Ownership of the memory to update: 'org', 'user', or 'agent'. Default: 'org'",
          enum: ["org", "user", "agent"]
        }
      },
      required: ["key"]
    }
  end

  @impl true
  def execute(input, context) do
    agent_id = Map.get(context, :agent_id) || Map.get(context, "agent_id")
    key = normalize_optional_text(Map.get(input, :key) || Map.get(input, "key"))
    scope = normalize_optional_text(Map.get(input, :scope) || Map.get(input, "scope")) || "org"
    user_id = Map.get(context, :user_id) || Map.get(context, "user_id")

    opts =
      [
        organization_id:
          Map.get(context, :organization_id) || Map.get(context, "organization_id"),
        user_id: user_id,
        agent_id: agent_id
      ]

    if is_nil(key) do
      {:error, "Provide a non-blank key to update"}
    else
      case App.Agents.get_memory(scope, key, opts) do
        %App.Agents.Memory{} = memory ->
          update_attrs =
            %{}
            |> maybe_put(
              "value",
              normalize_optional_text(Map.get(input, :value) || Map.get(input, "value"))
            )
            |> maybe_put("tags", Map.get(input, :tags) || Map.get(input, "tags"))

          if map_size(update_attrs) == 0 do
            {:error,
             "Provide at least one field to update: 'value' or 'tags'. Use memory_set to update value and tags together."}
          else
            memory
            |> App.Agents.Memory.changeset(update_attrs)
            |> App.Repo.update()
            |> case do
              {:ok, updated} ->
                {:ok,
                 "Memory updated: #{updated.key} (ownership: #{App.Agents.Memory.ownership(updated)}, tags: #{inspect(updated.tags)})"}

              {:error, changeset} ->
                {:error, format_errors(changeset)}
            end
          end

        nil ->
          {:error,
           "No memory found with key '#{key}' in ownership '#{scope}'. Use memory_set to create a new memory."}
      end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Enum.reduce(opts, message, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    "Failed to update memory: #{inspect(errors)}"
  end

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(value), do: value
end
