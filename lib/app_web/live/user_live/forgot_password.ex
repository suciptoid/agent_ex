defmodule AppWeb.UserLive.ForgotPassword do
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
                Forgot your password?
                <:subtitle>
                  Enter your account email and we'll send a secure reset link.
                </:subtitle>
              </.header>
            </div>

            <.form
              for={@form}
              id="forgot_password_form"
              phx-submit="send_email"
              class="mt-6 space-y-3"
            >
              <.input
                field={@form[:email]}
                type="email"
                label="Email"
                autocomplete="username"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
              />
              <.button
                class="w-full rounded-xl transition hover:brightness-95 dark:hover:brightness-110"
                phx-disable-with="Sending..."
              >
                Send reset instructions
              </.button>
            </.form>

            <p class="mt-5 text-center text-sm text-slate-500 dark:text-slate-400">
              Remember your password?
              <.link
                navigate={~p"/users/log-in"}
                class="font-medium text-slate-700 transition hover:text-slate-900 hover:underline dark:text-slate-200 dark:hover:text-white"
              >
                Log in
              </.link>
            </p>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)

    {:ok, assign(socket, form: to_form(%{"email" => email}, as: :user))}
  end

  @impl true
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Users.get_user_by_email(email) do
      Users.deliver_user_reset_password_instructions(user, &url(~p"/users/reset-password/#{&1}"))
    end

    info = "If your email is in our system, you will receive reset instructions shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/users/log-in")}
  end
end
