defmodule App.Agents.AlloyTools.SubagentWait do
  @moduledoc """
  Alloy tool for waiting on a spawned sub-agent report in the current parent chat room.
  """
  @behaviour Alloy.Tool

  alias App.Chat

  @impl true
  def name, do: "subagent_wait"

  @impl true
  def description do
    "Wait for a previously spawned sub-agent to finish and return its report from the current parent chat room."
  end

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        subagent_id: %{
          type: "string",
          description: "The child chat room id returned by subagent_spawn"
        },
        timeout_seconds: %{
          type: "integer",
          description: "Optional wait timeout in seconds, capped at 60",
          minimum: 1,
          maximum: 60
        }
      },
      required: ["subagent_id"]
    }
  end

  @impl true
  def execute(input, context) do
    with {:ok, parent_room} <- current_room(context),
         {:ok, subagent_id} <- validate_subagent_id(Map.get(input, "subagent_id")),
         {:ok, timeout_ms} <- validate_timeout_ms(Map.get(input, "timeout_seconds")),
         {:ok, report} <- Chat.wait_for_subagent_report(parent_room, subagent_id, timeout_ms) do
      {:ok,
       Jason.encode!(%{
         "subagent_id" => subagent_id,
         "status" => Atom.to_string(report.status),
         "agent_id" => report.agent_id,
         "content" => report.content || ""
       })}
    else
      {:error, :timeout} ->
        {:error, "Timed out while waiting for sub-agent #{Map.get(input, "subagent_id")}"}

      {:error, reason} ->
        {:error, format_reason(reason)}
    end
  end

  defp current_room(%{chat_room: %App.Chat.ChatRoom{} = chat_room}), do: {:ok, chat_room}
  defp current_room(_context), do: {:error, "sub-agent tools require a chat room context"}

  defp validate_subagent_id(subagent_id) when is_binary(subagent_id) do
    case String.trim(subagent_id) do
      "" -> {:error, "subagent_id cannot be blank"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp validate_subagent_id(_subagent_id), do: {:error, "subagent_id cannot be blank"}

  defp validate_timeout_ms(nil), do: {:ok, 60_000}

  defp validate_timeout_ms(timeout_seconds)
       when is_integer(timeout_seconds) and timeout_seconds in 1..60,
       do: {:ok, timeout_seconds * 1_000}

  defp validate_timeout_ms(_timeout_seconds),
    do: {:error, "timeout_seconds must be an integer between 1 and 60"}

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
