defmodule App.Chat.ChatRoomAgent do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_room_agents" do
    field :is_commander, :boolean, default: false

    belongs_to :chat_room, App.Chat.ChatRoom
    belongs_to :agent, App.Agents.Agent

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(chat_room_agent, attrs) do
    chat_room_agent
    |> cast(attrs, [:chat_room_id, :agent_id, :is_commander])
    |> validate_required([:chat_room_id, :agent_id])
    |> foreign_key_constraint(:chat_room_id)
    |> foreign_key_constraint(:agent_id)
    |> unique_constraint(:agent_id, name: :chat_room_agents_chat_room_id_agent_id_index)
  end
end
