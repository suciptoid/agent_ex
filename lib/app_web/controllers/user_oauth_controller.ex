defmodule AppWeb.UserOAuthController do
  use AppWeb, :controller

  plug :ensure_google_auth_enabled when action == :request
  plug Ueberauth

  alias Ueberauth.Auth
  alias Ueberauth.Failure

  alias App.Users
  alias AppWeb.UserAuth

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_auth: %Auth{} = auth}} = conn, _params) do
    case Users.get_or_register_user_by_google(google_user_attrs(auth)) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Signed in with Google successfully.")
        |> UserAuth.log_in_user(user)

      {:error, :email_not_verified} ->
        oauth_error(conn, "Google must return a verified email address.")

      {:error, :email_missing} ->
        oauth_error(conn, "Google did not provide an email address for this account.")

      {:error, :google_account_conflict} ->
        oauth_error(conn, "This email address is already linked to a different Google account.")

      {:error, %Ecto.Changeset{}} ->
        oauth_error(conn, "Unable to sign in with Google right now.")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: %Failure{} = failure}} = conn, _params) do
    oauth_error(conn, failure_message(failure))
  end

  defp google_user_attrs(%Auth{} = auth) do
    google_user = get_in(auth.extra.raw_info, [:user]) || %{}

    %{
      google_id: auth.uid,
      email: auth.info.email,
      name: google_user_name(auth.info),
      email_verified?: google_user["email_verified"] == true
    }
  end

  defp google_user_name(%{name: name}) when is_binary(name) and name != "", do: name

  defp google_user_name(%{first_name: first, last_name: last})
       when is_binary(first) and is_binary(last), do: "#{first} #{last}"

  defp google_user_name(%{first_name: first}) when is_binary(first) and first != "", do: first
  defp google_user_name(%{nickname: nick}) when is_binary(nick) and nick != "", do: nick
  defp google_user_name(_), do: nil

  defp oauth_error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/users/log-in")
  end

  defp failure_message(%Failure{errors: []}), do: "Google sign-in failed."

  defp failure_message(%Failure{errors: errors}) do
    Enum.map_join(errors, ", ", fn %{message: message} -> message end)
  end

  defp ensure_google_auth_enabled(conn, _opts) do
    if Users.google_auth_enabled?() do
      conn
    else
      conn
      |> put_flash(:error, "Google sign-in is not configured.")
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end
end
