defmodule App.Organizations.Organization do
  use Ecto.Schema

  import Ecto.Changeset

  alias App.Organizations.Settings

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :name, :string

    embeds_one :settings, Settings, on_replace: :update

    has_many :memberships, App.Organizations.Membership
    has_many :providers, App.Providers.Provider
    has_many :tools, App.Tools.Tool
    has_many :agents, App.Agents.Agent
    has_many :chat_rooms, App.Chat.ChatRoom

    many_to_many :users, App.Users.User,
      join_through: App.Organizations.Membership,
      join_keys: [organization_id: :id, user_id: :id]

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> cast_embed(:settings, with: &Settings.changeset/2)
    |> update_change(:name, &trim_text/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
  end

  defp trim_text(value) when is_binary(value), do: String.trim(value)
  defp trim_text(value), do: value
end
