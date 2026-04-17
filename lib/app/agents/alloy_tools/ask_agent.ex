defmodule App.Agents.AlloyTools.AskAgent do
  @moduledoc """
  Alloy tool for delegating a task to another agent in a multi-agent room.

  Configuration is passed via the Alloy context map:
  - `:chat_room` - the current chat room
  - `:agent_map` - map of agent_id => agent struct
  - `:messages_snapshot` - current conversation messages
  - `:callbacks` - orchestrator callback list
  - `:run_delegated_agent` - function/6 callback to the orchestrator's run_delegated_agent
  """
  @behaviour Alloy.Tool

  require Logger

  @impl true
  def name, do: "ask_agent"

  @impl true
  def description,
    do:
      "Ask another agent to handle a specific task. The agent will respond and their message will appear in the chat."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        agent_id: %{
          type: "string",
          description: "The id of the agent to ask"
        },
        instructions: %{
          type: "string",
          description: "Clear instructions for the target agent"
        }
      },
      required: ["agent_id", "instructions"]
    }
  end

  @impl true
  def execute(input, context) do
    agent_id = Map.get(input, "agent_id")
    instructions = normalize_text(Map.get(input, "instructions"))
    agent_map = Map.get(context, :agent_map, %{})
    chat_room = Map.get(context, :chat_room)
    callbacks = Map.get(context, :callbacks, [])
    messages_snapshot = Map.get(context, :messages_snapshot, [])
    run_delegated_agent = Map.get(context, :run_delegated_agent)

    case Map.get(agent_map, to_string(agent_id)) do
      nil ->
        {:error, "Unknown agent_id: #{agent_id}"}

      target_agent ->
        Logger.info("[AskAgent] ask_agent to #{target_agent.name} (#{agent_id})")

        placeholder_attrs = %{
          role: "assistant",
          content: nil,
          agent_id: target_agent.id,
          status: :pending,
          metadata: %{"delegated" => true, "tool_name" => "ask_agent"}
        }

        case App.Chat.create_message(chat_room, placeholder_attrs) do
          {:ok, placeholder_message} ->
            notify_callback(callbacks, :on_agent_message_created, [placeholder_message])

            if is_function(run_delegated_agent, 6) do
              {:ok, _pid} =
                Task.start(fn ->
                  run_delegated_agent.(
                    chat_room,
                    target_agent,
                    messages_snapshot,
                    instructions,
                    placeholder_message,
                    callbacks
                  )
                end)
            end

            {:ok, "Asked #{target_agent.name} to handle that. They will reply in the chat."}

          {:error, reason} ->
            {:error, "Failed to start delegated agent: #{inspect(reason)}"}
        end
    end
  end

  defp normalize_text(value) when is_binary(value), do: String.trim(value)
  defp normalize_text(value), do: value

  @callback_messages %{
    on_agent_message_created: :agent_message_created
  }

  defp notify_callback(callbacks, key, args) when is_list(callbacks) do
    case Keyword.get(callbacks, key) do
      callback when is_function(callback) ->
        apply(callback, args)

      _ ->
        # Fallback: send to :recipient pid if present (matches orchestrator convention)
        case Keyword.get(callbacks, :recipient) do
          recipient when is_pid(recipient) ->
            msg_name = Map.get(@callback_messages, key, key)
            send(recipient, List.to_tuple([msg_name | args]))

          _ ->
            :ok
        end
    end
  end

  defp notify_callback(_callbacks, _key, _args), do: :ok
end
