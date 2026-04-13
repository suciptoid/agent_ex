defmodule AppWeb.UserLive.LoginTest do
  use AppWeb.ConnCase, async: true

  import App.UsersFixtures
  import Phoenix.LiveViewTest

  describe "login page" do
    test "renders password and Google login options", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Create one here"
      assert has_element?(view, "#login_form_password")
      assert has_element?(view, "#login_google_button")
      assert has_element?(view, "#login_remember_me")
      assert has_element?(view, "a[href='/users/reset-password']")
      refute html =~ "Log in with email"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/log-in")
        |> follow_redirect(conn, ~p"/organizations/select")

      assert {:ok, _conn} = result
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/organizations/select"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the sign up link is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _login_live, registration_html} =
        lv
        |> element("main a", "Create one here")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert registration_html =~ "Create your account"
    end
  end
end
