defmodule App.Agents.Agent do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "agents" do
    field :name, :string
    field :system_prompt, :string
    field :model, :string
    field :extra_params, :map, default: %{}
    field :tools, {:array, :string}, default: []
    field :temperature, :float, virtual: true
    field :max_tokens, :integer, virtual: true

    belongs_to :provider, App.Providers.Provider
    belongs_to :user, App.Users.User

    has_many :chat_room_agents, App.Chat.ChatRoomAgent
    has_many :chat_rooms, through: [:chat_room_agents, :chat_room]

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(agent, attrs, opts \\ []) do
    agent
    |> cast(attrs, [
      :name,
      :system_prompt,
      :model,
      :provider_id,
      :tools,
      :temperature,
      :max_tokens
    ])
    |> update_change(:name, &trim_text/1)
    |> update_change(:system_prompt, &normalize_optional_text/1)
    |> update_change(:model, &trim_text/1)
    |> update_change(:tools, &normalize_tools/1)
    |> validate_required([:name, :model, :provider_id])
    |> validate_length(:name, max: 120)
    |> validate_format(:model, ~r/^[^:\s]+:.+$/, message: "must use provider:model format")
    |> validate_number(:temperature, greater_than_or_equal_to: 0, less_than_or_equal_to: 2)
    |> validate_number(:max_tokens, greater_than: 0)
    |> validate_tools(Keyword.get(opts, :allowed_tools, App.Agents.Tools.available_tools()))
    |> put_extra_params()
    |> foreign_key_constraint(:provider_id)
    |> foreign_key_constraint(:user_id)
  end

  defp normalize_tools(tool_names) do
    tool_names
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp validate_tools(changeset, allowed_tools) do
    invalid_tools =
      changeset
      |> get_field(:tools, [])
      |> Enum.reject(&(&1 in allowed_tools))

    if invalid_tools == [] do
      changeset
    else
      add_error(changeset, :tools, "contains unsupported tools")
    end
  end

  defp put_extra_params(changeset) do
    existing_extra_params = get_field(changeset, :extra_params) || %{}

    extra_params =
      existing_extra_params
      |> Map.drop(["temperature", "max_tokens"])
      |> maybe_put_extra_param("temperature", get_field(changeset, :temperature))
      |> maybe_put_extra_param("max_tokens", get_field(changeset, :max_tokens))

    put_change(changeset, :extra_params, extra_params)
  end

  defp maybe_put_extra_param(extra_params, _key, nil), do: extra_params
  defp maybe_put_extra_param(extra_params, key, value), do: Map.put(extra_params, key, value)

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_text(value), do: value
end
