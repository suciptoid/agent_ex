defmodule AppWeb.UserLive.ForgotPassword do
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
              Forgot your password?
              <:subtitle>
                Enter your account email and we will send a secure reset link.
              </:subtitle>
            </.header>
          </div>

          <div class="space-y-6 px-6 py-6 sm:px-8 sm:py-8">
            <.form for={@form} id="forgot_password_form" phx-submit="send_email" class="space-y-4">
              <.input
                field={@form[:email]}
                type="email"
                label="Email"
                autocomplete="username"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
              />
              <.button class="w-full rounded-2xl" phx-disable-with="Sending...">
                Send reset instructions
              </.button>
            </.form>

            <p class="text-center text-sm text-slate-500">
              Remember your password?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-sky-700 hover:underline">
                Return to login
              </.link>
            </p>
          </div>
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
     |> push_navigate(to: ~p"/users/log-in")}
  end
end
