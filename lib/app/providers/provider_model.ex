defmodule App.Providers.ProviderModel do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "provider_models" do
    field :model_id, :string
    field :name, :string
    field :supports_reasoning, :boolean, default: false
    field :context_window, :integer
    field :raw, :map, default: %{}
    field :status, :string, default: "active"

    belongs_to :provider, App.Providers.Provider

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(provider_model, attrs) do
    provider_model
    |> cast(attrs, [
      :model_id,
      :name,
      :supports_reasoning,
      :context_window,
      :raw,
      :status,
      :provider_id
    ])
    |> update_change(:model_id, &trim_text/1)
    |> update_change(:name, &trim_text/1)
    |> validate_required([:model_id, :provider_id])
    |> validate_length(:model_id, max: 255)
    |> validate_inclusion(:status, ["active", "inactive"])
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint(:model_id, name: :provider_models_provider_id_model_id_index)
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
