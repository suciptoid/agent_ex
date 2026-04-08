defmodule App.Organizations.Membership do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(owner admin member)
  @manager_roles ~w(owner admin)

  schema "organization_memberships" do
    field :role, :string

    belongs_to :organization, App.Organizations.Organization
    belongs_to :user, App.Users.User

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :organization_id, :user_id])
    |> validate_required([:role, :organization_id, :user_id])
    |> validate_inclusion(:role, @roles)
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id, name: :organization_memberships_org_user_index)
  end

  def roles, do: @roles
  def manager_roles, do: @manager_roles
end
