defmodule App.Providers.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "providers" do
    field :name, :string
    field :provider, :string
    field :api_key, App.Encrypted.Binary

    belongs_to :user, App.Users.User

    timestamps(type: :utc_datetime)
  end

  @valid_providers ~w(openai anthropic google gemini mistral cohere)

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :provider, :api_key])
    |> validate_required([:provider, :api_key])
    |> validate_inclusion(:provider, @valid_providers)
    |> foreign_key_constraint(:user_id)
  end
end
