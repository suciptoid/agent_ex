defmodule AppWeb.UserLive.ResetPasswordTest do
  use AppWeb.ConnCase, async: true

  import App.UsersFixtures
  import Phoenix.LiveViewTest

  alias App.Users

  setup do
    user = user_fixture()

    token =
      extract_user_token(fn url ->
        Users.deliver_user_reset_password_instructions(user, url)
      end)

    %{user: user, token: token}
  end

  describe "reset password page" do
    test "renders reset password form", %{conn: conn, token: token} do
      {:ok, view, html} = live(conn, ~p"/users/reset-password/#{token}")

      assert html =~ "Reset password"
      assert has_element?(view, "#reset_password_form")
    end

    test "redirects when token is invalid", %{conn: conn} do
      {:ok, conn} =
        conn
        |> live(~p"/users/reset-password/invalid")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Reset password link is invalid"
    end
  end

  describe "reset password submission" do
    test "resets password with valid data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      {:ok, conn} =
        lv
        |> form("#reset_password_form",
          user: %{
            password: "new valid password",
            password_confirmation: "new valid password"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password reset successfully"
    end

    test "shows errors for invalid data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      result =
        lv
        |> form("#reset_password_form",
          user: %{password: "short", password_confirmation: "different"}
        )
        |> render_submit()

      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end
end
