defmodule App.Tools do
  @moduledoc """
  The Tools context.
  """

  import Ecto.Query, warn: false

  alias App.Repo
  alias App.Tools.Tool
  alias App.Users.Scope

  def list_tools(%Scope{} = scope) do
    Tool
    |> where([tool], tool.user_id == ^scope.user.id)
    |> order_by([tool], asc: tool.name, desc: tool.inserted_at)
    |> Repo.all()
  end

  def list_tool_names(%Scope{} = scope) do
    Tool
    |> where([tool], tool.user_id == ^scope.user.id)
    |> order_by([tool], asc: tool.name)
    |> select([tool], tool.name)
    |> Repo.all()
  end

  def get_tool!(%Scope{} = scope, id) do
    Repo.get_by!(Tool, id: id, user_id: scope.user.id)
  end

  def update_tool(%Scope{} = scope, %Tool{} = tool, attrs) do
    ensure_user_owns_tool!(scope, tool)

    tool
    |> Tool.changeset(attrs)
    |> Repo.update()
  end

  def delete_tool(%Scope{} = scope, %Tool{} = tool) do
    ensure_user_owns_tool!(scope, tool)
    Repo.delete(tool)
  end

  def list_named_tools(user_id, names) when is_list(names) do
    Tool
    |> where([tool], tool.user_id == ^user_id and tool.name in ^names)
    |> Repo.all()
  end

  def create_tool(%Scope{} = scope, attrs) do
    %Tool{user_id: scope.user.id}
    |> Tool.changeset(attrs)
    |> Repo.insert()
  end

  def change_tool(%Tool{} = tool, attrs \\ %{}) do
    tool
    |> Tool.prepare_for_form()
    |> Tool.changeset(attrs)
  end

  defp ensure_user_owns_tool!(%Scope{} = scope, %Tool{user_id: user_id}) do
    if user_id != scope.user.id do
      raise Ecto.NoResultsError, query: Tool
    end
  end
end
