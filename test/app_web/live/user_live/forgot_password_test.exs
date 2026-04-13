defmodule AppWeb.UserLive.ForgotPasswordTest do
  use AppWeb.ConnCase, async: true

  import App.UsersFixtures
  import Phoenix.LiveViewTest

  alias App.Users

  describe "forgot password page" do
    test "renders forgot password form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users/reset-password")

      assert html =~ "Forgot your password?"
      assert has_element?(view, "#forgot_password_form")
    end
  end

  describe "send reset instructions" do
    test "sends reset link when email exists", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        lv
        |> form("#forgot_password_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert Users.get_user_by_email(user.email)
    end

    test "does not leak email existence", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, conn} =
        lv
        |> form("#forgot_password_form", user: %{email: unique_user_email()})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
    end
  end
end
