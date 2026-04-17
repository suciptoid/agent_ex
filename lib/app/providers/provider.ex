defmodule App.Providers.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  @provider_types ~w(openai anthropic openai_compat)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "providers" do
    field :name, :string
    field :provider, :string
    field :api_key, App.Encrypted.Binary
    field :base_url, :string
    field :provider_type, :string

    belongs_to :organization, App.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def provider_types, do: @provider_types

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :provider, :api_key, :base_url, :provider_type])
    |> validate_required([:provider, :api_key])
    |> validate_inclusion(:provider_type, @provider_types)
    |> maybe_infer_provider_type()
    |> validate_base_url()
    |> foreign_key_constraint(:organization_id)
  end

  defp maybe_infer_provider_type(changeset) do
    case get_field(changeset, :provider_type) do
      nil ->
        provider = get_field(changeset, :provider)

        type =
          case to_string(provider || "") do
            "anthropic" -> "anthropic"
            "openai" -> "openai"
            "" -> nil
            _other -> "openai_compat"
          end

        put_change(changeset, :provider_type, type)

      _existing ->
        changeset
    end
  end

  defp validate_base_url(changeset) do
    case get_field(changeset, :base_url) do
      nil ->
        changeset

      url when is_binary(url) ->
        if String.starts_with?(url, "http") do
          changeset
        else
          add_error(changeset, :base_url, "must be a valid HTTP URL")
        end
    end
  end
end
