defmodule App.Chat.ChatRoom do
  use Ecto.Schema

  import Ecto.Changeset

  @types [:chat, :archived, :task, :gateway]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_rooms" do
    field :title, :string
    field :type, Ecto.Enum, values: @types, default: :chat
    field :agent_ids, {:array, :binary_id}, virtual: true, default: []
    field :active_agent_id, :binary_id, virtual: true

    belongs_to :organization, App.Organizations.Organization
    belongs_to :parent, __MODULE__

    has_many :chat_room_agents, App.Chat.ChatRoomAgent
    has_many :agents, through: [:chat_room_agents, :agent]
    has_many :messages, App.Chat.Message
    has_many :child_rooms, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(chat_room, attrs) do
    chat_room
    |> cast(attrs, [:title, :type, :agent_ids, :active_agent_id, :parent_id])
    |> update_change(:title, &trim_text/1)
    |> update_change(:agent_ids, &normalize_agent_ids/1)
    |> validate_length(:title, max: 160)
    |> validate_agent_ids()
    |> validate_active_agent()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:parent_id)
  end

  defp validate_agent_ids(changeset) do
    case get_field(changeset, :agent_ids, []) do
      [] -> changeset
      _agent_ids -> changeset
    end
  end

  defp validate_active_agent(changeset) do
    active_agent_id = get_field(changeset, :active_agent_id)
    agent_ids = get_field(changeset, :agent_ids, [])

    cond do
      is_nil(active_agent_id) ->
        changeset

      active_agent_id in agent_ids ->
        changeset

      true ->
        add_error(changeset, :active_agent_id, "must be one of the selected agents")
    end
  end

  defp normalize_agent_ids(agent_ids) do
    agent_ids
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  def types, do: @types

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
