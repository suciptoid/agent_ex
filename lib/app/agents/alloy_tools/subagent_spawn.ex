defmodule App.Agents.AlloyTools.SubagentSpawn do
  @moduledoc """
  Alloy tool for spawning a sub-agent in a child chat room.
  """
  @behaviour Alloy.Tool

  alias App.Chat

  @impl true
  def name, do: "subagent_spawn"

  @impl true
  def description do
    "Spawn a sub-agent in a child chat room. Use this when another assigned agent should work independently on a focused sub-task."
  end

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        agent_id: %{
          type: "string",
          description: "The id of the assigned agent to spawn as the sub-agent"
        },
        prompt: %{
          type: "string",
          description: "The exact task for the sub-agent to complete"
        }
      },
      required: ["agent_id", "prompt"]
    }
  end

  @impl true
  def execute(input, context) do
    with {:ok, parent_room} <- current_room(context),
         {:ok, prompt} <- validate_prompt(Map.get(input, "prompt")),
         {:ok, target_agent} <- fetch_target_agent(input, context),
         {:ok, child_room} <-
           Chat.create_subagent_chat_room(parent_room, target_agent, %{title: nil}),
         {:ok, user_message} <- Chat.create_message(child_room, %{role: "user", content: prompt}),
         {:ok, child_placeholder} <-
           Chat.create_message(child_room, %{
             role: "assistant",
             content: nil,
             status: :pending,
             agent_id: target_agent.id,
             metadata: %{
               "subagent_child" => true,
               "parent_room_id" => parent_room.id
             }
           }),
         {:ok, _stream_pid} <-
           Chat.start_stream(
             child_room,
             [user_message],
             child_placeholder,
             extra_system_prompt: subagent_system_prompt(),
             extra_tools: [App.Agents.AlloyTools.SubagentReport],
             alloy_context: %{
               chat_room: child_room,
               parent_chat_room: parent_room,
               current_agent_id: target_agent.id
             }
           ) do
      {:ok,
       Jason.encode!(%{
         "subagent_id" => child_room.id,
         "agent_id" => target_agent.id,
         "status" => "running"
       })}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Failed to spawn sub-agent: #{format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, "Failed to spawn sub-agent: #{format_reason(reason)}"}
    end
  end

  defp current_room(%{chat_room: %App.Chat.ChatRoom{} = chat_room}), do: {:ok, chat_room}
  defp current_room(_context), do: {:error, "sub-agent tools require a chat room context"}

  defp validate_prompt(prompt) when is_binary(prompt) do
    case String.trim(prompt) do
      "" -> {:error, "prompt cannot be blank"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp validate_prompt(_prompt), do: {:error, "prompt cannot be blank"}

  defp fetch_target_agent(%{"agent_id" => agent_id}, context) do
    case Map.get(context, :agent_map, %{}) |> Map.get(to_string(agent_id)) do
      nil -> {:error, "Unknown agent_id: #{agent_id}"}
      agent -> {:ok, agent}
    end
  end

  defp subagent_system_prompt do
    """
    You are acting as a sub-agent for another agent in the same workspace.
    Complete only the delegated task from the user message in this room.

    If you can finish within the current run, respond normally in this child room so the parent can use `subagent_wait` to collect your result.
    If the task will take longer than the parent should wait or needs an asynchronous follow-up, use `subagent_report` when you have the final result so it is posted back to the parent room and the parent agent can resume there.
    """
    |> String.trim()
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(%{message: message}) when is_binary(message), do: message
  defp format_reason(%{__exception__: true} = exception), do: Exception.message(exception)
  defp format_reason(reason), do: inspect(reason)
end
