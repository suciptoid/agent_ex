defmodule AppWeb.UserLive.ResetPassword do
  use AppWeb, :live_view

  alias App.Users

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-[calc(100vh-10rem)] px-4 py-8 transition-colors sm:py-12 dark:bg-slate-950">
        <div class="mx-auto max-w-md">
          <section class="rounded-2xl border border-slate-200 bg-white/95 p-6 shadow-sm ring-1 ring-slate-950/5 backdrop-blur transition sm:p-8 dark:border-slate-800 dark:bg-slate-900 dark:ring-white/10">
            <div class="space-y-2">
              <p class="text-[0.7rem] font-semibold uppercase tracking-[0.14em] text-slate-500 dark:text-slate-400">
                Account recovery
              </p>
              <.header>
                Reset password
                <:subtitle>
                  Choose a password you haven't used before.
                </:subtitle>
              </.header>
            </div>

            <.form
              for={@form}
              id="reset_password_form"
              phx-submit="reset_password"
              phx-change="validate"
              class="mt-6 space-y-3"
            >
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
              <.button
                class="w-full rounded-xl transition hover:brightness-95 dark:hover:brightness-110"
                phx-disable-with="Resetting..."
              >
                Reset password
              </.button>
            </.form>
          </section>
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
         |> redirect(to: ~p"/users/log-in")}

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
         |> redirect(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user, action: :insert))}
    end
  end
end
