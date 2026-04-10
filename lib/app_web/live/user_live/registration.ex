defmodule AppWeb.UserLive.Registration do
  use AppWeb, :live_view

  alias App.Users
  alias App.Users.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md px-4 py-10 sm:px-6">
        <div class="overflow-hidden rounded-[2rem] border border-slate-200/70 bg-white shadow-[0_30px_90px_-45px_rgba(15,23,42,0.45)]">
          <div class="bg-[radial-gradient(circle_at_top,_rgba(16,185,129,0.14),_transparent_55%),linear-gradient(135deg,#f8fafc_0%,#ecfeff_45%,#ffffff_100%)] px-6 py-8 sm:px-8">
            <.header>
              Create your account
              <:subtitle>
                Already registered?
                <.link
                  navigate={~p"/users/log-in"}
                  class="font-semibold text-emerald-700 transition hover:text-emerald-600 hover:underline"
                >
                  Log in
                </.link>
                instead.
              </:subtitle>
            </.header>

            <p class="mt-4 text-sm leading-6 text-slate-600">
              Start with a password now, or let Google create the account from your verified email.
            </p>
          </div>

          <div class="space-y-6 px-6 py-6 sm:px-8 sm:py-8">
            <.link
              :if={@google_auth_enabled?}
              id="registration_google_button"
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
              Sign up with Google
            </.link>

            <div :if={@google_auth_enabled?} class="relative">
              <div class="absolute inset-0 flex items-center">
                <div class="w-full border-t border-slate-200"></div>
              </div>
              <div class="relative flex justify-center">
                <span class="bg-white px-3 text-[0.65rem] font-semibold uppercase tracking-[0.35em] text-slate-400">
                  Or create with email
                </span>
              </div>
            </div>

            <.form
              for={@form}
              id="registration_form"
              phx-submit="save"
              phx-change="validate"
              class="space-y-4"
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
              <.input
                field={@form[:password]}
                type="password"
                label="Password"
                autocomplete="new-password"
                spellcheck="false"
                required
              />
              <.input
                field={@form[:password_confirmation]}
                type="password"
                label="Confirm password"
                autocomplete="new-password"
                spellcheck="false"
                required
              />

              <.button phx-disable-with="Creating account..." class="w-full rounded-2xl">
                Create account
              </.button>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: AppWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset =
      Users.change_user_registration(%User{}, %{}, hash_password: false, validate_unique: false)

    {:ok,
     socket
     |> assign(:google_auth_enabled?, Users.google_auth_enabled?())
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Users.register_user(user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account created successfully. Log in to continue.")
         |> put_flash(:email, user.email)
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Users.change_user_registration(%User{}, user_params,
        hash_password: false,
        validate_unique: false
      )

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
