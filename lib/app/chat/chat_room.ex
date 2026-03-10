defmodule App.Chat.ChatRoom do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_rooms" do
    field :title, :string
    field :agent_ids, {:array, :binary_id}, virtual: true, default: []
    field :active_agent_id, :binary_id, virtual: true

    belongs_to :user, App.Users.User

    has_many :chat_room_agents, App.Chat.ChatRoomAgent
    has_many :agents, through: [:chat_room_agents, :agent]
    has_many :messages, App.Chat.Message

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(chat_room, attrs) do
    chat_room
    |> cast(attrs, [:title, :agent_ids, :active_agent_id])
    |> update_change(:title, &trim_text/1)
    |> update_change(:agent_ids, &normalize_agent_ids/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 160)
    |> validate_agent_ids()
    |> validate_active_agent()
    |> foreign_key_constraint(:user_id)
  end

  defp validate_agent_ids(changeset) do
    case get_field(changeset, :agent_ids, []) do
      [] -> add_error(changeset, :agent_ids, "select at least one agent")
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

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
