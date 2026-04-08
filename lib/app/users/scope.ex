defmodule App.Users.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `App.Users.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias App.Organizations.Organization
  alias App.Organizations.Membership
  alias App.Users.User

  defstruct user: nil, organization: nil, organization_role: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(user, opts_or_membership \\ nil)

  def for_user(%User{} = user, opts) when is_list(opts) do
    %__MODULE__{
      user: user,
      organization: Keyword.get(opts, :organization),
      organization_role: Keyword.get(opts, :organization_role)
    }
  end

  def for_user(%User{} = user, nil) do
    %__MODULE__{user: user}
  end

  def for_user(%User{} = user, %Membership{} = membership) do
    for_user(user,
      organization: membership.organization,
      organization_role: membership.role
    )
  end

  def for_user(nil, _opts_or_membership), do: nil

  def organization_selected?(%__MODULE__{organization: %Organization{}}), do: true
  def organization_selected?(_scope), do: false

  def organization_id!(%__MODULE__{organization: %Organization{id: organization_id}}),
    do: organization_id

  def organization_id!(_scope) do
    raise ArgumentError, "scope requires an active organization"
  end

  def manager?(%__MODULE__{organization_role: role}), do: role in ~w(owner admin)
  def manager?(_scope), do: false
end
