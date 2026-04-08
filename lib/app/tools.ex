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
      |> Tool.changeset(normalize_tool_attrs(attrs))
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
      |> Tool.changeset(normalize_tool_attrs(attrs))
      |> Repo.insert()
    end
  end

  def create_tool_for_organization(organization_id, attrs)
      when is_binary(organization_id) and is_map(attrs) do
    %Tool{organization_id: organization_id}
    |> Tool.changeset(normalize_tool_attrs(attrs))
    |> Repo.insert()
  end

  def change_tool(%Tool{} = tool, attrs \\ %{}) do
    tool
    |> Tool.prepare_for_form()
    |> Tool.changeset(normalize_tool_attrs(attrs))
  end

  def normalize_tool_attrs(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    attrs
    |> maybe_put_normalized_rows("param_rows", fn rows ->
      Enum.map(rows, &normalize_param_row/1)
    end)
    |> maybe_put_normalized_rows("header_rows", & &1)
  end

  def normalize_tool_attrs(_attrs), do: %{}

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

  defp normalize_rows(rows) when is_map(rows) do
    rows
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {_key, value} -> stringify_keys(value) end)
  end

  defp normalize_rows(rows) when is_list(rows), do: Enum.map(rows, &stringify_keys/1)
  defp normalize_rows(_rows), do: []

  defp maybe_put_normalized_rows(attrs, key, mapper) do
    if Map.has_key?(attrs, key) do
      Map.put(attrs, key, attrs |> Map.get(key) |> normalize_rows() |> mapper.())
    else
      attrs
    end
  end

  defp normalize_param_row(row) do
    value =
      row
      |> Map.get("value", "")
      |> to_string()
      |> String.trim()

    row
    |> Map.put("value", value)
    |> Map.put("source", if(value == "", do: "llm", else: "fixed"))
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_keys(value), do: value
end
