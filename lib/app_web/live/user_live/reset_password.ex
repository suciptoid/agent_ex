defmodule AppWeb.UserLive.ResetPassword do
  use AppWeb, :live_view

  alias App.Users

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md px-4 py-10 sm:px-6">
        <div class="overflow-hidden rounded-[2rem] border border-slate-200/70 bg-white shadow-[0_30px_90px_-45px_rgba(15,23,42,0.45)]">
          <div class="bg-[radial-gradient(circle_at_top,_rgba(59,130,246,0.14),_transparent_55%),linear-gradient(135deg,#f8fafc_0%,#eef2ff_52%,#ffffff_100%)] px-6 py-8 sm:px-8">
            <.header>
              Reset password
              <:subtitle>
                Create a new password for your account.
              </:subtitle>
            </.header>
          </div>

          <div class="space-y-6 px-6 py-6 sm:px-8 sm:py-8">
            <.form for={@form} id="reset_password_form" phx-submit="reset_password" phx-change="validate" class="space-y-4">
              <.input
                field={@form[:password]}
                type="password"
                label="New password"
                autocomplete="new-password"
                required
                phx-mounted={JS.focus()}
              />
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm new password"
                autocomplete="new-password"
                required
              />
              <.button class="w-full rounded-2xl" phx-disable-with="Resetting...">
                Reset password
              </.button>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Users.get_user_by_reset_password_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Reset password link is invalid or it has expired.")
         |> push_navigate(to: ~p"/users/log-in")}

      user ->
        form =
          user
          |> Users.change_user_password(%{}, hash_password: false)
          |> to_form(as: :user)

        {:ok, assign(socket, user: user, form: form)}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    form =
      socket.assigns.user
      |> Users.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form(as: :user)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Users.reset_user_password(socket.assigns.user, user_params) do
      {:ok, {_user, _expired_tokens}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user, action: :insert))}
    end
  end
end
