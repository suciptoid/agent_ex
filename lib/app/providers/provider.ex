defmodule App.Providers.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "providers" do
    field :name, :string
    field :provider, :string
    field :adapter, :string
    field :base_url, :string
    field :models_path, :string
    field :chat_path, :string
    field :api_key, App.Encrypted.Binary
    field :extra_headers, App.Encrypted.Map
    field :models_last_refreshed_at, :utc_datetime_usec
    field :models_last_refresh_error, :string

    belongs_to :organization, App.Organizations.Organization
    has_many :provider_models, App.Providers.ProviderModel

    timestamps(type: :utc_datetime)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :name,
      :provider,
      :adapter,
      :base_url,
      :models_path,
      :chat_path,
      :api_key,
      :extra_headers,
      :models_last_refreshed_at,
      :models_last_refresh_error
    ])
    |> update_change(:name, &trim_text/1)
    |> update_change(:provider, &trim_text/1)
    |> update_change(:adapter, &trim_text/1)
    |> update_change(:base_url, &trim_text/1)
    |> update_change(:models_path, &trim_text/1)
    |> update_change(:chat_path, &trim_text/1)
    |> update_change(:models_last_refresh_error, &trim_text/1)
    |> validate_required([:provider, :api_key])
    |> validate_inclusion(:provider, App.Providers.valid_provider_values())
    |> validate_format(:base_url, ~r/^https?:\/\/\S+$/, message: "must be a valid http(s) URL")
    |> validate_format(:models_path, ~r/^\/\S+$/, message: "must start with /")
    |> validate_chat_path()
    |> foreign_key_constraint(:organization_id)
  end

  defp validate_chat_path(changeset) do
    case get_field(changeset, :chat_path) do
      nil ->
        changeset

      "" ->
        changeset

      _chat_path ->
        validate_format(changeset, :chat_path, ~r/^\/\S+$/, message: "must start with /")
    end
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
