defmodule App.Agents.AlloyTools.ChannelSendMessage do
  @moduledoc false
  @behaviour Alloy.Tool

  alias App.Chat.ChatRoom
  alias App.Gateways
  alias App.Repo

  @impl true
  def name, do: "channel_send_message"

  @impl true
  def description do
    "Send a notification to the configured gateway-linked chat room. The message is persisted as an assistant reply in that room and relayed through the active channel when available."
  end

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        message: %{
          type: "string",
          description: "The message to deliver to the configured notification channel"
        }
      },
      required: ["message"]
    }
  end

  @impl true
  def execute(input, context) do
    message = Map.get(input, "message", "")

    with %ChatRoom{} = chat_room <- notification_chat_room(context),
         {:ok, _message} <-
           Gateways.notify_chat_room(chat_room, message,
             agent_id: Map.get(context, :agent_id),
             metadata: notification_metadata(context)
           ) do
      {:ok, "Delivered notification to #{chat_room.title || chat_room.id}"}
    else
      nil -> {:error, "No notification chat room is configured for this task"}
      {:error, :blank_content} -> {:error, "Message cannot be blank"}
      {:error, reason} -> {:error, "Failed to send message: #{inspect(reason)}"}
    end
  end

  defp notification_chat_room(context) do
    case Map.get(context, :notification_chat_room) do
      %ChatRoom{} = chat_room ->
        chat_room

      _other ->
        case Map.get(context, :notification_chat_room_id) do
          chat_room_id when is_binary(chat_room_id) -> Repo.get(ChatRoom, chat_room_id)
          _other -> nil
        end
    end
  end

  defp notification_metadata(context) do
    %{}
    |> put_metadata("task_id", Map.get(context, :task_id))
    |> put_metadata("task_name", Map.get(context, :task_name))
    |> put_metadata("task_chat_room_id", Map.get(context, :task_chat_room_id))
    |> Map.put("task_notification", true)
  end

  defp put_metadata(metadata, _key, nil), do: metadata
  defp put_metadata(metadata, key, value), do: Map.put(metadata, key, value)
end
