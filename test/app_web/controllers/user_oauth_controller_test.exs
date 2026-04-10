defmodule AppWeb.UserOAuthControllerTest do
  use AppWeb.ConnCase, async: true

  alias Ueberauth.Auth
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Auth.Info
  alias Ueberauth.Failure
  alias Ueberauth.Failure.Error

  alias App.Users

  import App.UsersFixtures

  describe "GET /auth/google/callback" do
    test "creates a new user and logs them in", %{conn: conn} do
      email = unique_user_email()

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, google_auth("google-new", email, true))

      conn = AppWeb.UserOAuthController.callback(conn, %{})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/organizations/select"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Signed in with Google successfully."

      assert user = Users.get_user_by_email(email)
      assert user.google_id == "google-new"
      assert user.confirmed_at
    end

    test "links Google to an existing user by verified email", %{conn: conn} do
      user = unconfirmed_user_fixture()

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, google_auth("google-linked", user.email, true))

      conn = AppWeb.UserOAuthController.callback(conn, %{})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/organizations/select"

      assert linked_user = Users.get_user!(user.id)
      assert linked_user.google_id == "google-linked"
      assert linked_user.confirmed_at
    end

    test "redirects when Google email is not verified", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:ueberauth_auth, google_auth("google-unverified", unique_user_email(), false))

      conn = AppWeb.UserOAuthController.callback(conn, %{})

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Google must return a verified email address."
    end

    test "redirects when ueberauth returns a failure", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(
          :ueberauth_failure,
          %Failure{
            provider: :google,
            strategy: Ueberauth.Strategy.Google,
            errors: [%Error{message: "access denied"}]
          }
        )

      conn = AppWeb.UserOAuthController.callback(conn, %{})

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "access denied"
    end
  end

  defp google_auth(google_id, email, email_verified?) do
    %Auth{
      uid: google_id,
      provider: :google,
      strategy: Ueberauth.Strategy.Google,
      info: %Info{email: email},
      extra: %Extra{raw_info: %{user: %{"email_verified" => email_verified?}}}
    }
  end
end
