defmodule App.Agents.AlloyTools.Handover do
  @moduledoc """
  Alloy tool for multi-agent handover. Transfers the active agent role.

  Configuration is passed via the Alloy context map:
  - `:chat_room` - the current chat room
  - `:agent_map` - map of agent_id => agent struct
  - `:callbacks` - orchestrator callback list
  """
  @behaviour Alloy.Tool

  require Logger

  @impl true
  def name, do: "handover"

  @impl true
  def description,
    do: "Transfer the active agent role to another agent in this room."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        agent_id: %{
          type: "string",
          description: "The id of the agent to make active"
        },
        reason: %{
          type: "string",
          description: "Optional reason for the handover"
        }
      },
      required: ["agent_id"]
    }
  end

  @impl true
  def execute(input, context) do
    agent_id = Map.get(input, "agent_id")
    reason = Map.get(input, "reason")
    agent_map = Map.get(context, :agent_map, %{})
    chat_room = Map.get(context, :chat_room)
    callbacks = Map.get(context, :callbacks, [])

    case Map.get(agent_map, to_string(agent_id)) do
      nil ->
        {:error, "Unknown agent_id: #{agent_id}"}

      target_agent ->
        Logger.info("[Handover] Handover to agent #{target_agent.name} (#{agent_id})")

        case App.Chat.set_active_agent(chat_room, target_agent.id) do
          :ok ->
            notify_callback(callbacks, :on_active_agent_changed, [target_agent.id])

            msg =
              if blank?(reason),
                do: "Handed over to #{target_agent.name}.",
                else: "Handed over to #{target_agent.name}: #{reason}"

            {:ok, msg}

          {:error, err} ->
            {:error, "Failed to set active agent: #{inspect(err)}"}
        end
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp notify_callback(callbacks, key, args) do
    case Keyword.get(callbacks, key) do
      callback when is_function(callback) -> apply(callback, args)
      _ -> :ok
    end
  end
end
