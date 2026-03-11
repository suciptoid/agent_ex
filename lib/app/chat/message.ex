defmodule App.Chat.Message do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @roles ~w(user assistant system tool)
  @statuses [:pending, :streaming, :error, :completed]
  @incomplete_statuses [:pending, :streaming]

  schema "chat_messages" do
    field :position, :integer
    field :role, :string
    field :content, :string
    field :status, Ecto.Enum, values: @statuses, default: :completed
    field :metadata, :map, default: %{}

    belongs_to :chat_room, App.Chat.ChatRoom
    belongs_to :agent, App.Agents.Agent

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:position, :role, :content, :status, :agent_id, :metadata])
    |> update_change(:content, &trim_text/1)
    |> validate_required([:position, :role])
    |> validate_content_required()
    |> validate_number(:position, greater_than: 0)
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:chat_room_id)
    |> foreign_key_constraint(:agent_id)
  end

  defp validate_content_required(changeset) do
    status = get_field(changeset, :status, :completed)

    if status in @incomplete_statuses do
      changeset
    else
      validate_required(changeset, [:content])
    end
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
