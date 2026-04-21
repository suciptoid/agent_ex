defmodule App.Providers.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "providers" do
    field :name, :string
    field :provider, :string
    field :api_key, App.Encrypted.Binary
    field :base_url, :string

    belongs_to :organization, App.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def alloy_provider_type(%__MODULE__{provider: "anthropic"}), do: "anthropic"
  def alloy_provider_type(%__MODULE__{provider: "openai"}), do: "openai"
  def alloy_provider_type(%__MODULE__{provider: "gemini"}), do: "gemini"
  def alloy_provider_type(%__MODULE__{provider: "google"}), do: "gemini"
  def alloy_provider_type(%__MODULE__{}), do: "openai_compat"

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :provider, :api_key, :base_url])
    |> validate_required([:provider, :api_key])
    |> validate_base_url()
    |> foreign_key_constraint(:organization_id)
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
