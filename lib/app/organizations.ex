defmodule App.Organizations do
  @moduledoc """
  The Organizations context.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias App.Organizations.{Membership, Organization}
  alias App.Repo
  alias App.Users.Scope
  alias App.Users.User

  def list_memberships(%User{} = user) do
    Membership
    |> where([membership], membership.user_id == ^user.id)
    |> join(:inner, [membership], organization in assoc(membership, :organization))
    |> preload([membership, organization], organization: organization)
    |> order_by([_membership, organization], asc: fragment("lower(?)", organization.name))
    |> Repo.all()
  end

  def list_organization_ids(%User{} = user) do
    Membership
    |> where([membership], membership.user_id == ^user.id)
    |> select([membership], membership.organization_id)
    |> Repo.all()
  end

  def count_organizations(%User{} = user) do
    Repo.aggregate(
      from(membership in Membership, where: membership.user_id == ^user.id),
      :count,
      :id
    )
  end

  def get_membership(%User{} = user, organization_id) when is_binary(organization_id) do
    Membership
    |> where(
      [membership],
      membership.user_id == ^user.id and membership.organization_id == ^organization_id
    )
    |> preload([:organization])
    |> Repo.one()
  end

  def get_organization(%Scope{user: %User{} = user}, organization_id)
      when is_binary(organization_id) do
    case get_membership(user, organization_id) do
      %Membership{organization: organization} -> organization
      nil -> nil
    end
  end

  def change_organization(%Organization{} = organization, attrs \\ %{}) do
    Organization.changeset(organization, attrs)
  end

  def create_organization(%User{} = user, attrs) do
    Multi.new()
    |> Multi.insert(:organization, Organization.changeset(%Organization{}, attrs))
    |> Multi.insert(:membership, fn %{organization: organization} ->
      Membership.changeset(%Membership{}, %{
        organization_id: organization.id,
        user_id: user.id,
        role: "owner"
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{organization: organization}} -> {:ok, organization}
      {:error, :organization, changeset, _changes} -> {:error, changeset}
      {:error, :membership, changeset, _changes} -> {:error, changeset}
    end
  end

  def manager?(%Scope{} = scope), do: Scope.manager?(scope)

  def resolve_active_membership(%User{} = user, active_organization_id \\ nil) do
    memberships = list_memberships(user)
    membership = active_membership(memberships, active_organization_id)
    {memberships, membership}
  end

  def scope_for_membership(%User{} = user, nil), do: Scope.for_user(user)

  def scope_for_membership(%User{} = user, %Membership{} = membership) do
    Scope.for_user(user,
      organization: membership.organization,
      organization_role: membership.role
    )
  end

  def manager_role?(role) when is_binary(role), do: role in Membership.manager_roles()
  def manager_role?(_role), do: false

  defp active_membership([], _active_organization_id), do: nil

  defp active_membership(memberships, active_organization_id)
       when is_binary(active_organization_id) do
    Enum.find(memberships, &(&1.organization_id == active_organization_id)) ||
      active_membership(memberships, nil)
  end

  defp active_membership([membership], nil), do: membership
  defp active_membership(_memberships, nil), do: nil
end
