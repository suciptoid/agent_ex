defmodule App.Gateways.Gateway.Config do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :agent_id, :binary_id
    field :allow_all_users, :boolean, default: true
    field :allowed_user_ids, {:array, :string}, default: []
    field :welcome_message, :string
    field :allowed_updates, {:array, :string}, default: ["message", "callback_query"]
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :agent_id,
      :allow_all_users,
      :allowed_user_ids,
      :welcome_message,
      :allowed_updates
    ])
    |> update_change(:welcome_message, &trim_text/1)
    |> update_change(:allowed_user_ids, &normalize_list/1)
    |> update_change(:allowed_updates, &normalize_list/1)
  end

  defp normalize_list(list) when is_list(list) do
    list
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp normalize_list(other), do: other

  defp trim_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_text(value), do: value
end
