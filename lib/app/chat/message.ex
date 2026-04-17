defmodule App.Chat.Message do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @roles ~w(user assistant system tool checkpoint)
  @statuses [:pending, :streaming, :error, :completed]
  @incomplete_statuses [:pending, :streaming]
  @running_statuses [:pending, :streaming]

  schema "chat_messages" do
    field :position, :integer
    field :role, :string
    field :content, :string
    field :name, :string
    field :tool_call_id, :string
    field :status, Ecto.Enum, values: @statuses, default: :completed
    field :metadata, :map, default: %{}

    belongs_to :chat_room, App.Chat.ChatRoom
    belongs_to :agent, App.Agents.Agent
    belongs_to :parent_message, __MODULE__
    has_many :tool_messages, __MODULE__, foreign_key: :parent_message_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :position,
      :role,
      :content,
      :name,
      :tool_call_id,
      :status,
      :agent_id,
      :metadata,
      :parent_message_id
    ])
    |> update_change(:content, &trim_text/1)
    |> update_change(:name, &trim_text/1)
    |> validate_required([:position, :role])
    |> validate_number(:position, greater_than: 0)
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> validate_tool_message_fields()
    |> validate_content_required()
    |> foreign_key_constraint(:chat_room_id)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:parent_message_id)
    |> unique_constraint(:position, name: :chat_messages_chat_room_id_position_index)
    |> unique_constraint(:tool_call_id, name: :chat_messages_parent_tool_call_id_index)
  end

  def thinking(%__MODULE__{} = message), do: metadata_value(message, "thinking")

  def tool_calls(%__MODULE__{} = message) do
    case metadata_value(message, "tool_calls") do
      tool_calls when is_list(tool_calls) -> tool_calls
      _other -> []
    end
  end

  def tool_call_turns(%__MODULE__{} = message) do
    case metadata_value(message, "tool_call_turns") do
      turns when is_list(turns) ->
        turns

      _other ->
        legacy_tool_call_turns(message)
    end
  end

  def tool_responses(%__MODULE__{} = message) do
    case loaded_tool_messages(message) do
      [] -> legacy_tool_responses(message)
      tool_messages -> Enum.map(tool_messages, &tool_message_to_response/1)
    end
  end

  def tool_call_ids(%__MODULE__{} = message) do
    message
    |> tool_call_turns()
    |> Enum.flat_map(&turn_tool_calls/1)
    |> Enum.map(&tool_call_id/1)
    |> Enum.reject(&is_nil/1)
  end

  def checkpoint?(%__MODULE__{role: "checkpoint"}), do: true
  def checkpoint?(%__MODULE__{}), do: false

  defp validate_content_required(changeset) do
    status = get_field(changeset, :status, :completed)
    role = get_field(changeset, :role)
    metadata = get_field(changeset, :metadata, %{})

    if role == "tool" or status in @incomplete_statuses or
         assistant_tool_call_turn?(role, metadata) do
      changeset
    else
      validate_required(changeset, [:content])
    end
  end

  defp validate_tool_message_fields(changeset) do
    case get_field(changeset, :role) do
      "tool" ->
        validate_required(changeset, [:name, :tool_call_id, :parent_message_id])

      _other ->
        changeset
    end
  end

  defp loaded_tool_messages(%__MODULE__{tool_messages: tool_messages})
       when is_list(tool_messages) do
    tool_messages
    |> Enum.filter(&(&1.role == "tool"))
    |> Enum.sort_by(& &1.position)
  end

  defp loaded_tool_messages(_message), do: []

  defp legacy_tool_call_turns(message) do
    case legacy_tool_responses(message) do
      [] ->
        []

      tool_responses ->
        [
          %{
            "tool_calls" =>
              Enum.map(tool_responses, fn tool_response ->
                %{}
                |> put_map_value("id", Map.get(tool_response, "id"))
                |> put_map_value("name", Map.get(tool_response, "name"))
                |> put_map_value("arguments", Map.get(tool_response, "arguments"))
              end)
          }
        ]
    end
  end

  defp legacy_tool_responses(message) do
    message
    |> metadata_value("tool_responses")
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  defp tool_message_to_response(%__MODULE__{} = message) do
    %{}
    |> put_map_value("id", message.tool_call_id)
    |> put_map_value("name", message.name)
    |> put_map_value("arguments", metadata_value(message, "arguments"))
    |> put_map_value("content", message.content)
    |> Map.put("status", metadata_value(message, "tool_status") || tool_message_status(message))
  end

  defp tool_message_status(%__MODULE__{status: status}) when status in @running_statuses,
    do: "running"

  defp tool_message_status(%__MODULE__{status: :error}), do: "error"
  defp tool_message_status(%__MODULE__{}), do: "ok"

  defp turn_tool_calls(%{} = turn) do
    turn
    |> Map.get("tool_calls", Map.get(turn, :tool_calls, []))
    |> List.wrap()
  end

  defp tool_call_id(%{} = tool_call), do: Map.get(tool_call, "id") || Map.get(tool_call, :id)
  defp tool_call_id(_tool_call), do: nil

  defp metadata_value(%__MODULE__{metadata: metadata}, key) when is_map(metadata),
    do: Map.get(metadata, key)

  defp metadata_value(%__MODULE__{}, _key), do: nil

  defp assistant_tool_call_turn?("assistant", metadata) when is_map(metadata) do
    metadata
    |> Map.get("tool_calls", Map.get(metadata, :tool_calls, []))
    |> List.wrap()
    |> Kernel.!=([])
  end

  defp assistant_tool_call_turn?(_role, _metadata), do: false

  defp put_map_value(map, _key, nil), do: map
  defp put_map_value(map, key, value), do: Map.put(map, key, value)

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
