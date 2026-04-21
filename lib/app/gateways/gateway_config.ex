defmodule App.Gateways.Gateway.Config do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :agent_id, :binary_id
    field :agent_ids, {:array, :binary_id}, default: []
    field :allow_all_users, :boolean, default: true
    field :allowed_user_ids, {:array, :string}, default: []
    field :welcome_message, :string
    field :allowed_updates, {:array, :string}, default: ["message", "callback_query"]
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :agent_id,
      :agent_ids,
      :allow_all_users,
      :allowed_user_ids,
      :welcome_message,
      :allowed_updates
    ])
    |> update_change(:agent_id, &normalize_optional_id/1)
    |> update_change(:agent_ids, &normalize_list/1)
    |> update_change(:welcome_message, &trim_text/1)
    |> update_change(:allowed_user_ids, &normalize_list/1)
    |> update_change(:allowed_updates, &normalize_list/1)
    |> put_agent_ids_from_default_agent()
    |> ensure_default_agent()
    |> validate_default_agent()
  end

  defp normalize_list(list) when is_list(list) do
    list
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp normalize_list(other), do: other

  defp normalize_optional_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_id(value), do: value

  defp put_agent_ids_from_default_agent(changeset) do
    case {get_field(changeset, :agent_ids, []), get_field(changeset, :agent_id)} do
      {[], agent_id} when is_binary(agent_id) and agent_id != "" ->
        put_change(changeset, :agent_ids, [agent_id])

      _other ->
        changeset
    end
  end

  defp ensure_default_agent(changeset) do
    case {get_field(changeset, :agent_id), get_field(changeset, :agent_ids, [])} do
      {nil, [agent_id | _rest]} ->
        put_change(changeset, :agent_id, agent_id)

      _other ->
        changeset
    end
  end

  defp validate_default_agent(changeset) do
    case {get_field(changeset, :agent_id), get_field(changeset, :agent_ids, [])} do
      {nil, _agent_ids} ->
        changeset

      {agent_id, agent_ids} ->
        if agent_id in agent_ids do
          changeset
        else
          add_error(changeset, :agent_id, "must be one of the assigned agents")
        end
    end
  end

  defp trim_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_text(value), do: value
end
