defmodule AppWeb.UserSessionController do
  use AppWeb, :controller

  alias App.Users
  alias AppWeb.UserAuth

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}, info) do
    if user = Users.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  defp create(conn, %{"user" => %{"email" => email}}, _info) do
    conn
    |> put_flash(:error, "Password is required")
    |> put_flash(:email, String.slice(email, 0, 160))
    |> redirect(to: ~p"/users/log-in")
  end

  defp create(conn, _params, _info) do
    conn
    |> put_flash(:error, "Invalid login request")
    |> redirect(to: ~p"/users/log-in")
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    {:ok, {_user, expired_tokens}} = Users.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
