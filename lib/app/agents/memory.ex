defmodule App.Agents.Memory do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_memories" do
    field :key, :string
    field :value, :string
    field :tags, {:array, :string}, default: []

    belongs_to :agent, App.Agents.Agent
    belongs_to :organization, App.Organizations.Organization
    belongs_to :user, App.Users.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:key, :value, :tags, :agent_id, :organization_id, :user_id])
    |> validate_required([:key, :value, :organization_id])
    |> validate_length(:key, max: 255)
    |> update_change(:key, &trim_text/1)
    |> update_change(:tags, &normalize_tags/1)
    |> normalize_ownership_fields()
    |> validate_ownership()
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:unique_user_key,
      name: :agent_memories_unique_user_key_idx,
      message: "memory with this key already exists for this ownership"
    )
    |> unique_constraint(:unique_org_key,
      name: :agent_memories_unique_org_key_idx,
      message: "memory with this key already exists for this ownership"
    )
    |> unique_constraint(:unique_agent_key,
      name: :agent_memories_unique_agent_key_idx,
      message: "memory with this key already exists for this ownership"
    )
  end

  def ownership(%__MODULE__{agent_id: nil, user_id: nil}), do: :org
  def ownership(%__MODULE__{agent_id: nil, user_id: user_id}) when not is_nil(user_id), do: :user

  def ownership(%__MODULE__{agent_id: agent_id, user_id: nil}) when not is_nil(agent_id),
    do: :agent

  def ownership(%__MODULE__{}), do: :invalid

  defp normalize_ownership_fields(changeset) do
    case {get_field(changeset, :agent_id), get_field(changeset, :user_id)} do
      {nil, nil} ->
        changeset

      {nil, _user_id} ->
        changeset

      {_agent_id, nil} ->
        changeset

      {_agent_id, _user_id} ->
        changeset
    end
  end

  defp validate_ownership(changeset) do
    case {get_field(changeset, :agent_id), get_field(changeset, :user_id)} do
      {nil, nil} ->
        changeset

      {agent_id, nil} when not is_nil(agent_id) ->
        changeset

      {nil, user_id} when not is_nil(user_id) ->
        changeset

      {_agent_id, _user_id} ->
        add_error(changeset, :user_id, "can't be set together with agent_id")
    end
  end

  defp normalize_tags(tags) do
    tags
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
