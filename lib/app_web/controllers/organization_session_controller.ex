defmodule AppWeb.OrganizationSessionController do
  use AppWeb, :controller

  alias App.Organizations

  def update(conn, %{"id" => organization_id} = params) do
    user = conn.assigns.current_scope.user

    case Organizations.get_membership(user, organization_id) do
      nil ->
        conn
        |> put_flash(:error, "You do not have access to that organization.")
        |> redirect(to: ~p"/organizations/select")

      _membership ->
        conn
        |> put_session(:active_organization_id, organization_id)
        |> delete_session(:organization_return_to)
        |> redirect(
          to:
            safe_return_to(params["return_to"]) || get_session(conn, :organization_return_to) ||
              ~p"/dashboard"
        )
    end
  end

  defp safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path
    end
  end

  defp safe_return_to(_path), do: nil
end
