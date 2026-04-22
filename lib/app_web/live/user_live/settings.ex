defmodule AppWeb.UserLive.Settings do
  use AppWeb, :live_view

  alias App.Users

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      current_scope={@current_scope}
      sidebar_chat_rooms={@sidebar_chat_rooms}
      sidebar_organizations={@sidebar_organizations}
    >
      <div class="flex h-full min-h-0 flex-col p-4 pt-20 sm:px-5 sm:pb-5 sm:pt-20 lg:p-6">
        <div class="space-y-8">
          <%!-- Page Header --%>
          <div class="border-b border-gray-200 dark:border-gray-700 pb-6">
            <h1 class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
              Account Settings
            </h1>
            <p class="mt-2 text-lg text-gray-600 dark:text-gray-300">
              Manage your account email address and password settings
            </p>
          </div>

          <%!-- Name Settings Card --%>
          <.card>
            <.card_header>
              <.card_title>Name</.card_title>
              <.card_description>Update your display name</.card_description>
            </.card_header>
            <.card_content>
              <.form
                for={@name_form}
                id="name_form"
                phx-submit="update_name"
                phx-change="validate_name"
              >
                <.input
                  field={@name_form[:name]}
                  type="text"
                  label="Name"
                  autocomplete="name"
                  placeholder="Your display name"
                />
                <div class="mt-4">
                  <.button phx-disable-with="Saving...">Save Name</.button>
                </div>
              </.form>
            </.card_content>
          </.card>

          <%!-- Email Settings Card --%>
          <.card>
            <.card_header>
              <.card_title>Email Address</.card_title>
              <.card_description>Update your email address</.card_description>
            </.card_header>
            <.card_content>
              <.form
                for={@email_form}
                id="email_form"
                phx-submit="update_email"
                phx-change="validate_email"
              >
                <.input
                  field={@email_form[:email]}
                  type="email"
                  label="Email"
                  autocomplete="username"
                  spellcheck="false"
                  required
                />
                <div class="mt-4">
                  <.button phx-disable-with="Changing...">Change Email</.button>
                </div>
              </.form>
            </.card_content>
          </.card>

          <%!-- Password Settings Card --%>
          <.card>
            <.card_header>
              <.card_title>Password</.card_title>
              <.card_description>Update your password</.card_description>
            </.card_header>
            <.card_content>
              <.form
                for={@password_form}
                id="password_form"
                action={~p"/users/update-password"}
                method="post"
                phx-change="validate_password"
                phx-submit="update_password"
                phx-trigger-action={@trigger_submit}
              >
                <input
                  name={@password_form[:email].name}
                  type="hidden"
                  id="hidden_user_email"
                  spellcheck="false"
                  value={@current_email}
                />
                <.input
                  field={@password_form[:password]}
                  type="password"
                  label="New password"
                  autocomplete="new-password"
                  spellcheck="false"
                  required
                />
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password"
                  label="Confirm new password"
                  autocomplete="new-password"
                  spellcheck="false"
                />
                <div class="mt-4">
                  <.button phx-disable-with="Saving...">
                    Save Password
                  </.button>
                </div>
              </.form>
            </.card_content>
          </.card>
        </div>
      </div>
    </Layouts.dashboard>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Users.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Users.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Users.change_user_password(user, %{}, hash_password: false)
    name_changeset = Users.change_user_name(user, %{name: user.name})

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:name_form, to_form(name_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_name", %{"user" => user_params}, socket) do
    name_form =
      socket.assigns.current_scope.user
      |> Users.change_user_name(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, name_form: name_form)}
  end

  def handle_event("update_name", %{"user" => user_params}, socket) do
    user = socket.assigns.current_scope.user

    case Users.update_user_name(user, user_params) do
      {:ok, _user} ->
        {:noreply, put_flash(socket, :info, "Name updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, name_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Users.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Users.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Users.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Users.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user

    case Users.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
