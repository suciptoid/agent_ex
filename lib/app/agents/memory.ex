defmodule App.Agents.Memory do
  use Ecto.Schema

  import Ecto.Changeset

  @scopes ~w(org user)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "agent_memories" do
    field :key, :string
    field :value, :string
    field :tags, {:array, :string}, default: []
    field :scope, :string

    belongs_to :agent, App.Agents.Agent
    belongs_to :organization, App.Organizations.Organization
    belongs_to :user, App.Users.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :key,
      :value,
      :tags,
      :scope,
      :agent_id,
      :organization_id,
      :user_id
    ])
    |> validate_required([:key, :value, :scope, :agent_id, :organization_id])
    |> validate_inclusion(:scope, @scopes)
    |> validate_length(:key, max: 255)
    |> update_change(:key, &trim_text/1)
    |> update_change(:tags, &normalize_tags/1)
    |> validate_scope_fields()
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:unique_user_key,
      name: :agent_memories_unique_user_key_idx,
      message: "memory with this key already exists for this scope"
    )
    |> unique_constraint(:unique_org_key,
      name: :agent_memories_unique_org_key_idx,
      message: "memory with this key already exists for this scope"
    )
  end

  defp validate_scope_fields(changeset) do
    scope = get_field(changeset, :scope)

    cond do
      scope == "user" and is_nil(get_field(changeset, :user_id)) ->
        add_error(changeset, :user_id, "is required for user-scoped memories")

      not is_nil(get_field(changeset, :user_id)) and scope not in ["user"] ->
        add_error(changeset, :scope, "must be user when user_id is set")

      true ->
        changeset
    end
  end

  defp normalize_tags(tags) do
    tags
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&String.trim/1)
    |> Enum.uniq()
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
