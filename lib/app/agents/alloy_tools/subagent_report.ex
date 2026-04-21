defmodule App.Agents.AlloyTools.SubagentReport do
  @moduledoc """
  Alloy tool for reporting a sub-agent result back to the parent chat room and
  resuming the parent agent there.
  """
  @behaviour Alloy.Tool

  alias App.Chat
  alias App.Chat.ChatRoom

  @impl true
  def name, do: "subagent_report"

  @impl true
  def description do
    "Report a finished sub-agent result back to the parent chat room and wake the parent agent there."
  end

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        report: %{
          type: "string",
          description: "The final report to post back to the parent chat room"
        }
      },
      required: ["report"]
    }
  end

  @impl true
  def execute(input, context) do
    with {:ok, child_room} <- child_room(context),
         {:ok, parent_room} <- parent_room(context, child_room),
         {:ok, report_content} <- validate_report(Map.get(input, "report")),
         {:ok, report_message} <-
           create_parent_report(parent_room, child_room, report_content, context),
         {:ok, resumed?} <- maybe_resume_parent_room(parent_room, child_room) do
      {:ok,
       Jason.encode!(%{
         "subagent_id" => child_room.id,
         "report_message_id" => report_message.id,
         "status" => "reported",
         "resumed_parent" => resumed?
       })}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, format_changeset_errors(changeset)}

      {:error, reason} ->
        {:error, format_reason(reason)}
    end
  end

  defp child_room(%{chat_room: %ChatRoom{parent_id: parent_id} = chat_room})
       when is_binary(parent_id),
       do: {:ok, chat_room}

  defp child_room(%{chat_room: %ChatRoom{}}),
    do: {:error, "subagent_report can only be used from a child chat room"}

  defp child_room(_context), do: {:error, "subagent_report requires a child chat room context"}

  defp parent_room(%{parent_chat_room: %ChatRoom{} = parent_chat_room}, %ChatRoom{
         parent_id: parent_id
       })
       when parent_chat_room.id == parent_id,
       do: {:ok, Chat.preload_chat_room(parent_chat_room)}

  defp parent_room(_context, _child_room),
    do: {:error, "subagent_report requires the parent chat room context"}

  defp validate_report(report) when is_binary(report) do
    case String.trim(report) do
      "" -> {:error, "report cannot be blank"}
      trimmed -> {:ok, trimmed}
    end
  end

  defp validate_report(_report), do: {:error, "report cannot be blank"}

  defp create_parent_report(parent_room, child_room, report_content, context) do
    Chat.create_message(parent_room, %{
      role: "assistant",
      content: report_content,
      agent_id: Map.get(context, :current_agent_id),
      status: :completed,
      metadata: %{
        "delegated" => true,
        "subagent" => true,
        "tool_name" => name(),
        "subagent_room_id" => child_room.id,
        "parent_room_id" => parent_room.id
      }
    })
    |> case do
      {:ok, report_message} ->
        Chat.broadcast_chat_room(parent_room.id, {:agent_message_created, report_message})
        {:ok, report_message}

      {:error, _reason} = error ->
        error
    end
  end

  defp maybe_resume_parent_room(parent_room, child_room) do
    parent_room = Chat.preload_chat_room(parent_room)

    cond do
      Chat.room_stream_running?(parent_room) ->
        {:ok, false}

      true ->
        case Chat.start_parent_followup_stream(
               parent_room,
               child_room.id,
               parent_followup_prompt(child_room)
             ) do
          {:ok, _pid} -> {:ok, true}
          {:error, :no_active_agent} -> {:ok, false}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp parent_followup_prompt(child_room) do
    """
    A sub-agent has just reported back from child room #{child_room.id}.
    Continue the conversation in this parent room using the latest sub-agent report message.
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
