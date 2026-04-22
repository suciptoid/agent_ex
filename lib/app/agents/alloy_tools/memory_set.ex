defmodule App.Agents.AlloyTools.MemorySet do
  @moduledoc false
  @behaviour Alloy.Tool

  @impl true
  def name, do: "memory_set"

  @impl true
  def description,
    do:
      "Save a memory for later recall across conversations. Use to store user preferences, facts, profile info, or notes. If a memory with the same key and scope already exists, it will be updated."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        key: %{
          type: "string",
          description:
            "A unique identifier for this memory (e.g. 'user_timezone', 'preferred_language')"
        },
        value: %{
          type: "string",
          description: "The memory content to store"
        },
        tags: %{
          type: "array",
          description:
            "Tags categorizing this memory. Standard tags: 'preferences', 'profile', 'fact', 'instruction', 'note'",
          items: %{type: "string"}
        },
        scope: %{
          type: "string",
          description:
            "Memory scope. 'org' = shared across org, 'user' = per-user. Default: 'org'",
          enum: ["org", "user"]
        }
      },
      required: ["key", "value"]
    }
  end

  @impl true
  def execute(input, context) do
    requested_scope = Map.get(input, :scope) || Map.get(input, "scope") || "org"
    user_id = Map.get(context, :user_id) || Map.get(context, "user_id")

    scope =
      if requested_scope == "user" and is_nil(user_id) do
        "org"
      else
        requested_scope
      end

    attrs =
      %{
        "agent_id" => Map.get(context, :agent_id) || Map.get(context, "agent_id"),
        "organization_id" =>
          Map.get(context, :organization_id) || Map.get(context, "organization_id"),
        "user_id" => user_id,
        "key" => Map.get(input, :key) || Map.get(input, "key"),
        "value" => Map.get(input, :value) || Map.get(input, "value"),
        "tags" => Map.get(input, :tags) || Map.get(input, "tags") || [],
        "scope" => scope
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case App.Agents.set_memory(attrs) do
      {:ok, memory} ->
        {:ok,
         "Memory saved: #{memory.key} (scope: #{memory.scope}, tags: #{inspect(memory.tags)})"}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp format_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Enum.reduce(opts, message, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    "Failed to save memory: #{inspect(errors)}"
  end
end
