defmodule App.Organizations do
  @moduledoc """
  The Organizations context.
  """

  import Ecto.Query, warn: false

  alias App.Agents
  alias App.Agents.Agent
  alias Ecto.Multi
  alias App.Organizations.{Membership, Organization, Secret, Settings}
  alias App.Repo
  alias App.Users.Scope
  alias App.Users.User

  @default_agent_secret_key "default_agent"

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

  def get_secret(%Scope{} = scope, key) when is_binary(key) do
    Repo.get_by(Secret,
      organization_id: Scope.organization_id!(scope),
      key: String.trim(key)
    )
  end

  def get_secret_value(%Scope{} = scope, key) when is_binary(key) do
    case get_secret(scope, key) do
      %Secret{value: value} -> value
      nil -> nil
    end
  end

  def default_agent_id(%Scope{} = scope) do
    case get_secret_value(scope, @default_agent_secret_key) do
      agent_id when is_binary(agent_id) and agent_id != "" -> agent_id
      _other -> nil
    end
  end

  def default_agent(%Scope{} = scope) do
    default_agent_id(scope)
    |> case do
      agent_id when is_binary(agent_id) ->
        Agents.get_agent(scope, agent_id) || List.first(Agents.list_agents(scope))

      _other ->
        List.first(Agents.list_agents(scope))
    end
  end

  def change_settings(%Scope{} = scope, attrs \\ %{}) do
    %Settings{default_agent_id: default_agent_id(scope)}
    |> Settings.changeset(attrs)
    |> validate_default_agent(scope)
  end

  def update_settings(%Scope{} = scope, attrs) do
    with :ok <- authorize_manager(scope) do
      changeset = change_settings(scope, attrs)

      if changeset.valid? do
        default_agent_id = Ecto.Changeset.get_field(changeset, :default_agent_id)

        case put_secret(scope, @default_agent_secret_key, default_agent_id) do
          {:ok, _secret_or_nil} -> {:ok, default_agent_id(scope)}
          {:error, _reason} = error -> error
        end
      else
        {:error, changeset}
      end
    end
  end

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

  defp put_secret(%Scope{} = scope, key, value) when is_binary(key) do
    normalized_key = String.trim(key)
    secret = get_secret(scope, normalized_key)

    cond do
      blank?(value) and is_nil(secret) ->
        {:ok, nil}

      blank?(value) ->
        Repo.delete(secret)

      is_nil(secret) ->
        %Secret{organization_id: Scope.organization_id!(scope)}
        |> Secret.changeset(%{key: normalized_key, value: value})
        |> Repo.insert()

      true ->
        secret
        |> Secret.changeset(%{value: value})
        |> Repo.update()
    end
  end

  defp validate_default_agent(changeset, %Scope{} = scope) do
    case Ecto.Changeset.get_field(changeset, :default_agent_id) do
      nil ->
        changeset

      "" ->
        Ecto.Changeset.put_change(changeset, :default_agent_id, nil)

      agent_id ->
        case Agents.get_agent(scope, agent_id) do
          %Agent{} ->
            changeset

          nil ->
            Ecto.Changeset.add_error(
              changeset,
              :default_agent_id,
              "must belong to the current organization"
            )
        end
    end
  end

  defp authorize_manager(%Scope{} = scope) do
    if Scope.manager?(scope), do: :ok, else: {:error, :forbidden}
  end

  defp blank?(value), do: value in [nil, ""]

  defp active_membership([], _active_organization_id), do: nil

  defp active_membership(memberships, active_organization_id)
       when is_binary(active_organization_id) do
    Enum.find(memberships, &(&1.organization_id == active_organization_id)) ||
      active_membership(memberships, nil)
  end

  defp active_membership([membership], nil), do: membership
  defp active_membership(_memberships, nil), do: nil
end
