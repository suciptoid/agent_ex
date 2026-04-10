defmodule AppWeb.UserLive.RegistrationTest do
  use AppWeb.ConnCase, async: true

  import App.UsersFixtures
  import Phoenix.LiveViewTest

  describe "Registration page" do
    test "renders password and Google signup options", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users/register")

      assert html =~ "Create your account"
      assert has_element?(view, "#registration_form")
      assert has_element?(view, "#registration_google_button")
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/organizations/select")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      password = valid_user_password()
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(
          user: %{
            "email" => "with spaces",
            "password" => password,
            "password_confirmation" => password
          }
        )

      assert result =~ "Create your account"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "creates account but does not log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "Account created successfully. Log in to continue."
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      user = user_fixture(%{email: "test@email.com"})
      password = valid_user_password()

      result =
        lv
        |> form("#registration_form",
          user: %{
            "email" => user.email,
            "password" => password,
            "password_confirmation" => password
          }
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in link is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert login_html =~ "Log in"
    end
  end
end
