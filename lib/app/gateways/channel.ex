defmodule App.Gateways.Channel do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:active, :closed, :blocked]

  schema "gateway_channels" do
    field :external_chat_id, :string
    field :external_user_id, :string
    field :external_username, :string
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :metadata, :map, default: %{}

    belongs_to :gateway, App.Gateways.Gateway
    belongs_to :chat_room, App.Chat.ChatRoom

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :external_chat_id,
      :external_user_id,
      :external_username,
      :status,
      :metadata,
      :chat_room_id
    ])
    |> validate_required([:external_chat_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:gateway_id)
    |> foreign_key_constraint(:chat_room_id)
    |> unique_constraint([:gateway_id, :external_chat_id])
  end
end
