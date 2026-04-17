defmodule App.Agents.AlloyTools.UpdateTitle do
  @moduledoc """
  Alloy tool for setting the chat room title.

  Configuration is passed via the Alloy context map:
  - `:chat_room` - the current chat room
  - `:callbacks` - orchestrator callback list
  """
  @behaviour Alloy.Tool

  @impl true
  def name, do: "update_chatroom_title"

  @impl true
  def description,
    do:
      "Set the title of the current conversation. Call once at the start with a concise, descriptive title based on the user's first message."

  @impl true
  def input_schema do
    %{
      type: "object",
      properties: %{
        title: %{
          type: "string",
          description: "A concise title (max 60 chars) summarizing the conversation topic"
        }
      },
      required: ["title"]
    }
  end

  @impl true
  def execute(input, context) do
    title = Map.get(input, "title", "")
    chat_room = Map.get(context, :chat_room)
    callbacks = Map.get(context, :callbacks, [])

    if is_function(Keyword.get(callbacks, :on_title_updated), 1) do
      callback = Keyword.fetch!(callbacks, :on_title_updated)
      callback.(title)
    else
      if chat_room, do: App.Chat.update_chat_room_title(chat_room, title)
    end

    {:ok, "Title set to: #{title}"}
  end
end
