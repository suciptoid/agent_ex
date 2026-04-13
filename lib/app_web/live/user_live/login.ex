defmodule AppWeb.UserLive.Login do
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
              Log in
              <:subtitle>
                <%= if @current_scope && @current_scope.user do %>
                  Reauthenticate to continue with sensitive account changes.
                <% else %>
                  Need an account?
                  <.link
                    navigate={~p"/users/register"}
                    class="font-semibold text-sky-700 transition hover:text-sky-600 hover:underline"
                  >
                    Create one here
                  </.link>
                  .
                <% end %>
              </:subtitle>
            </.header>

            <p class="mt-4 text-sm leading-6 text-slate-600">
              Sign in with your password or continue with Google using the same verified email.
            </p>
          </div>

          <div class="space-y-6 px-6 py-6 sm:px-8 sm:py-8">
            <.link
              :if={@google_auth_enabled?}
              id="login_google_button"
              href={~p"/auth/google"}
              class={[
                "group flex w-full items-center justify-center gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm font-medium text-slate-700 transition",
                "shadow-[0_12px_30px_-24px_rgba(15,23,42,0.9)] hover:-translate-y-0.5 hover:border-slate-300 hover:bg-slate-50"
              ]}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true" class="size-5">
                <path
                  d="M21.805 10.023H12v3.955h5.627c-.243 1.275-.97 2.355-2.062 3.081v2.56h3.34c1.956-1.801 3.08-4.456 3.08-7.619 0-.664-.06-1.302-.18-1.977Z"
                  fill="#4285F4"
                />
                <path
                  d="M12 22c2.79 0 5.13-.925 6.84-2.381l-3.34-2.56c-.925.622-2.11.992-3.5.992-2.688 0-4.964-1.815-5.78-4.254H2.77v2.64A10 10 0 0 0 12 22Z"
                  fill="#34A853"
                />
                <path
                  d="M6.22 13.797A5.997 5.997 0 0 1 5.89 12c0-.624.11-1.228.33-1.797V7.563H2.77A10 10 0 0 0 2 12c0 1.6.383 3.114 1.07 4.437l3.15-2.64Z"
                  fill="#FBBC05"
                />
                <path
                  d="M12 5.95c1.52 0 2.88.523 3.95 1.55l2.96-2.96C17.125 2.91 14.785 2 12 2A10 10 0 0 0 2.77 7.563l3.45 2.64C7.036 7.765 9.312 5.95 12 5.95Z"
                  fill="#EA4335"
                />
              </svg>
              Continue with Google
            </.link>

            <div :if={@google_auth_enabled?} class="relative">
              <div class="absolute inset-0 flex items-center">
                <div class="w-full border-t border-slate-200"></div>
              </div>
              <div class="relative flex justify-center">
                <span class="bg-white px-3 text-[0.65rem] font-semibold uppercase tracking-[0.35em] text-slate-400">
                  Or use email
                </span>
              </div>
            </div>

            <.form
              for={@form}
              id="login_form_password"
              action={~p"/users/log-in"}
              phx-submit="submit_password"
              phx-trigger-action={@trigger_submit}
              class="space-y-4"
            >
              <.input
                readonly={!!(@current_scope && @current_scope.user)}
                field={@form[:email]}
                type="email"
                label="Email"
                autocomplete="username"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
                id="login_password_email"
              />
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                autocomplete="current-password"
                spellcheck="false"
                required
              />
              <.checkbox
                field={@form[:remember_me]}
                label="Remember me on this device"
                id="login_remember_me"
              />
              <div class="flex items-center justify-between gap-4">
                <.link
                  navigate={~p"/users/reset-password"}
                  class="text-sm font-semibold text-sky-700 transition hover:text-sky-600 hover:underline"
                >
                  Forgot password?
                </.link>
                <.button class="rounded-2xl px-8">
                  Log in
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        current_scope_email(socket.assigns.current_scope)

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       form: form,
       trigger_submit: false,
       google_auth_enabled?: Users.google_auth_enabled?()
     )}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  defp current_scope_email(%{user: %{email: email}}) when is_binary(email), do: email
  defp current_scope_email(_current_scope), do: nil
end
