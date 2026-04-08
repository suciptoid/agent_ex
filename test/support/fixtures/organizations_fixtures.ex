defmodule App.OrganizationsFixtures do
  alias App.Organizations
  alias App.Organizations.Membership
  alias App.Organizations.Organization
  alias App.Repo
  alias App.Users.Scope

  def organization_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Organization #{System.unique_integer([:positive])}"
    })
  end

  def organization_fixture(user, attrs \\ %{}) do
    {:ok, organization} =
      user
      |> Organizations.create_organization(organization_attrs(attrs))

    organization
  end

  def membership_fixture(user, organization, role \\ "member") do
    {:ok, membership} =
      %Membership{}
      |> Membership.changeset(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role
      })
      |> Repo.insert()

    Repo.preload(membership, [:organization])
  end

  def organization_scope_fixture(user, opts \\ []) do
    organization = Keyword.get(opts, :organization) || existing_or_create_organization(user)
    role = Keyword.get(opts, :role)

    membership =
      case {Organizations.get_membership(user, organization.id), role} do
        {%Membership{} = membership, nil} ->
          membership

        {%Membership{} = membership, requested_role} when membership.role == requested_role ->
          membership

        {%Membership{} = membership, requested_role} when is_binary(requested_role) ->
          {:ok, updated_membership} =
            membership
            |> Membership.changeset(%{role: requested_role})
            |> Repo.update()

          Repo.preload(updated_membership, [:organization])

        {nil, requested_role} when is_binary(requested_role) ->
          membership_fixture(user, organization, requested_role)

        {nil, _role} ->
          membership_fixture(user, organization, "member")
      end

    Scope.for_user(user, membership)
  end

  defp existing_or_create_organization(user) do
    case Organizations.list_memberships(user) do
      [%Membership{organization: %Organization{} = organization} | _rest] -> organization
      [] -> organization_fixture(user)
    end
  end
end
