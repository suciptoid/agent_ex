defmodule App.Organizations.Secret do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_secrets" do
    field :key, :string
    field :value, App.Encrypted.Binary

    belongs_to :organization, App.Organizations.Organization

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(secret, attrs) do
    secret
    |> cast(attrs, [:key, :value, :organization_id])
    |> update_change(:key, &trim_text/1)
    |> update_change(:value, &trim_text/1)
    |> validate_required([:key, :value, :organization_id])
    |> validate_length(:key, max: 120)
    |> foreign_key_constraint(:organization_id)
    |> unique_constraint(:key, name: :organization_secrets_organization_id_key_index)
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
