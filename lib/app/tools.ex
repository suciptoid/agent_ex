defmodule App.Tools do
  @moduledoc """
  The Tools context.
  """

  import Ecto.Query, warn: false

  alias App.Organizations.Membership
  alias App.Repo
  alias App.Tools.Tool
  alias App.Users.Scope
  alias App.Users.User

  def list_tools(%Scope{} = scope) do
    Tool
    |> where([tool], tool.organization_id == ^Scope.organization_id!(scope))
    |> order_by([tool], asc: tool.name, desc: tool.inserted_at)
    |> Repo.all()
  end

  def count_tools(%Scope{} = scope) do
    Repo.aggregate(
      from(tool in Tool, where: tool.organization_id == ^Scope.organization_id!(scope)),
      :count,
      :id
    )
  end

  def list_tool_names(%Scope{} = scope) do
    Tool
    |> where([tool], tool.organization_id == ^Scope.organization_id!(scope))
    |> order_by([tool], asc: tool.name)
    |> select([tool], tool.name)
    |> Repo.all()
  end

  def get_tool!(%Scope{} = scope, id) do
    Repo.get_by!(Tool, id: id, organization_id: Scope.organization_id!(scope))
  end

  def get_tool(%Scope{} = scope, id) do
    Repo.get_by(Tool, id: id, organization_id: Scope.organization_id!(scope))
  end

  def get_tool_for_user(%User{} = user, id) do
    Tool
    |> join(:inner, [tool], membership in Membership,
      on: membership.organization_id == tool.organization_id
    )
    |> where([tool, membership], membership.user_id == ^user.id and tool.id == ^id)
    |> select([tool, _membership], tool)
    |> Repo.one()
  end

  def update_tool(%Scope{} = scope, %Tool{} = tool, attrs) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_tool(scope, tool) do
      tool
      |> Tool.changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_tool(%Scope{} = scope, %Tool{} = tool) do
    with :ok <- authorize_manager(scope),
         :ok <- ensure_organization_owns_tool(scope, tool) do
      Repo.delete(tool)
    end
  end

  def list_named_tools(organization_id, names)
      when is_binary(organization_id) and is_list(names) do
    Tool
    |> where([tool], tool.organization_id == ^organization_id and tool.name in ^names)
    |> Repo.all()
  end

  def create_tool(%Scope{} = scope, attrs) do
    with :ok <- authorize_manager(scope) do
      %Tool{organization_id: Scope.organization_id!(scope)}
      |> Tool.changeset(attrs)
      |> Repo.insert()
    end
  end

  def change_tool(%Tool{} = tool, attrs \\ %{}) do
    tool
    |> Tool.prepare_for_form()
    |> Tool.changeset(attrs)
  end

  defp authorize_manager(%Scope{} = scope) do
    if Scope.manager?(scope), do: :ok, else: {:error, :forbidden}
  end

  defp ensure_organization_owns_tool(%Scope{} = scope, %Tool{organization_id: organization_id}) do
    if organization_id == Scope.organization_id!(scope) do
      :ok
    else
      raise Ecto.NoResultsError, query: Tool
    end
  end
end
