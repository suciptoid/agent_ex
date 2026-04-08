defmodule App.Gateways.Gateway do
  use Ecto.Schema

  import Ecto.Changeset

  alias App.Gateways.Gateway.Config

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types [:telegram, :whatsapp_api]
  @statuses [:active, :inactive, :error]

  schema "gateways" do
    field :name, :string
    field :type, Ecto.Enum, values: @types
    field :token, App.Encrypted.Binary
    field :webhook_secret, :string
    field :status, Ecto.Enum, values: @statuses, default: :active

    embeds_one :config, Config, on_replace: :update

    belongs_to :organization, App.Organizations.Organization

    has_many :channels, App.Gateways.Channel

    timestamps(type: :utc_datetime_usec)
  end

  def types, do: @types

  def changeset(gateway, attrs) do
    gateway
    |> ensure_config_embed()
    |> cast(attrs, [:name, :type, :token, :status])
    |> cast_embed(:config, with: &Config.changeset/2)
    |> update_change(:name, &trim_text/1)
    |> validate_required([:name, :type, :token])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:name, max: 120)
    |> maybe_generate_webhook_secret()
    |> foreign_key_constraint(:organization_id)
  end

  defp ensure_config_embed(%__MODULE__{config: nil} = gateway),
    do: %{gateway | config: %Config{}}

  defp ensure_config_embed(gateway), do: gateway

  defp maybe_generate_webhook_secret(changeset) do
    case get_field(changeset, :webhook_secret) do
      nil ->
        put_change(changeset, :webhook_secret, generate_webhook_secret())

      _existing ->
        changeset
    end
  end

  defp generate_webhook_secret do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
