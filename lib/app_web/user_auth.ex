defmodule AppWeb.UserAuth do
  use AppWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias App.Chat
  alias App.Organizations
  alias App.Users
  alias App.Users.Scope

  @max_cookie_age_in_days 14
  @remember_me_cookie "_app_web_user_remember_me"
  @active_organization_session_key :active_organization_id
  @organization_return_to_session_key :organization_return_to

  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  @session_reissue_age_in_days 7

  @doc """
  Logs the user in.

  Redirects to the session's `:user_return_to` path
  or falls back to the organization-aware signed-in path.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)
    active_organization_id = login_active_organization_id(conn, user)

    conn
    |> create_or_extend_session(user, params)
    |> sync_active_organization_session(active_organization_id)
    |> delete_session(@organization_return_to_session_key)
    |> redirect(to: user_return_to || default_signed_in_path(active_organization_id))
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Users.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      AppWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, token_inserted_at} <- Users.get_user_by_session_token(token) do
      {scope, active_organization_id} = authenticated_scope(conn, user)

      conn
      |> assign(:current_scope, scope)
      |> sync_active_organization_session(active_organization_id)
      |> maybe_reissue_user_session_token(user, token_inserted_at)
    else
      nil -> assign(conn, :current_scope, Scope.for_user(nil))
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      else
        nil
      end
    end
  end

  defp authenticated_scope(conn, user) do
    active_organization_id = get_session(conn, @active_organization_session_key)

    {_memberships, membership} =
      Organizations.resolve_active_membership(user, active_organization_id)

    {Organizations.scope_for_membership(user, membership),
     membership && membership.organization_id}
  end

  defp login_active_organization_id(conn, user) do
    active_organization_id = get_session(conn, @active_organization_session_key)

    {_memberships, membership} =
      Organizations.resolve_active_membership(user, active_organization_id)

    membership && membership.organization_id
  end

  defp sync_active_organization_session(conn, nil),
    do: delete_session(conn, @active_organization_session_key)

  defp sync_active_organization_session(conn, active_organization_id) do
    put_session(conn, @active_organization_session_key, active_organization_id)
  end

  defp default_signed_in_path(nil), do: ~p"/organizations/select"
  defp default_signed_in_path(_active_organization_id), do: ~p"/dashboard"

  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user, %{})
    else
      conn
    end
  end

  defp create_or_extend_session(conn, user, params) do
    token = Users.generate_user_session_token(user)
    remember_me = get_session(conn, :user_remember_me)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  defp renew_session(
         %Plug.Conn{assigns: %{current_scope: %Scope{user: %Users.User{id: user_id}}}} = conn,
         %Users.User{id: user_id}
       ) do
    conn
  end

  defp renew_session(conn, _user) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:user_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      AppWeb.Endpoint.broadcast(user_session_topic(token), "disconnect", %{})
    end)
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_scope in LiveViews.
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      scope = socket.assigns.current_scope

      socket =
        socket
        |> Phoenix.Component.assign_new(:sidebar_chat_rooms, fn ->
          if Scope.organization_selected?(scope) do
            App.Chat.list_chat_rooms_for_sidebar(scope)
          else
            []
          end
        end)
        |> Phoenix.Component.assign_new(:sidebar_organizations, fn ->
          Organizations.list_memberships(scope.user)
        end)
        |> attach_sidebar_chat_room_hook()

      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      active_organization_id = session_active_organization_id(session)

      {user, _token_inserted_at} =
        if user_token = session["user_token"] do
          Users.get_user_by_session_token(user_token)
        end || {nil, nil}

      if user do
        {_memberships, membership} =
          Organizations.resolve_active_membership(user, active_organization_id)

        Organizations.scope_for_membership(user, membership)
      else
        Scope.for_user(nil)
      end
    end)
  end

  defp session_active_organization_id(session) do
    session["active_organization_id"] || session[:active_organization_id]
  end

  defp attach_sidebar_chat_room_hook(socket) do
    case socket do
      %{private: %{lifecycle: _lifecycle}} ->
        Phoenix.LiveView.attach_hook(
          socket,
          :sidebar_chat_room_actions,
          :handle_event,
          &handle_sidebar_chat_room_event/3
        )

      _other ->
        socket
    end
  end

  defp handle_sidebar_chat_room_event("delete-chat-room", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    socket =
      case Chat.get_chat_room(scope, id) do
        nil ->
          socket
          |> refresh_sidebar_chat_rooms()
          |> Phoenix.LiveView.put_flash(:error, "Conversation not found.")

        chat_room ->
          case Chat.delete_chat_room(scope, chat_room) do
            {:ok, _deleted_chat_room} ->
              socket
              |> refresh_sidebar_chat_rooms()
              |> refresh_chat_room_dependent_assigns()
              |> Phoenix.LiveView.put_flash(:info, "Conversation deleted.")
              |> maybe_navigate_after_chat_delete(chat_room.id)

            {:error, _reason} ->
              socket
              |> refresh_sidebar_chat_rooms()
              |> Phoenix.LiveView.put_flash(:error, "Failed to delete conversation.")
          end
      end

    {:halt, socket}
  end

  defp handle_sidebar_chat_room_event(_event, _params, socket), do: {:cont, socket}

  defp refresh_sidebar_chat_rooms(socket) do
    scope = socket.assigns.current_scope

    Phoenix.Component.assign(
      socket,
      :sidebar_chat_rooms,
      if(Scope.organization_selected?(scope),
        do: Chat.list_chat_rooms_for_sidebar(scope),
        else: []
      )
    )
  end

  defp refresh_chat_room_dependent_assigns(socket) do
    scope = socket.assigns.current_scope

    socket
    |> maybe_assign(:recent_chat_rooms, fn -> Chat.list_recent_chat_rooms(scope, 5) end)
    |> maybe_assign(:conversations_count, fn -> Chat.count_chat_rooms(scope) end)
  end

  defp maybe_navigate_after_chat_delete(socket, deleted_chat_room_id) do
    case Map.get(socket.assigns, :chat_room) do
      %{id: ^deleted_chat_room_id} ->
        Phoenix.LiveView.push_navigate(socket, to: ~p"/chat")

      _other ->
        socket
    end
  end

  defp maybe_assign(socket, key, loader) when is_function(loader, 0) do
    if Map.has_key?(socket.assigns, key) do
      Phoenix.Component.assign(socket, key, loader.())
    else
      socket
    end
  end

  @doc "Returns the path to redirect to after log in."
  def signed_in_path(%Plug.Conn{assigns: %{current_scope: %Scope{} = scope}}),
    do: signed_in_path(scope)

  def signed_in_path(%Phoenix.LiveView.Socket{assigns: %{current_scope: %Scope{} = scope}}),
    do: signed_in_path(scope)

  def signed_in_path(%Scope{user: %Users.User{}} = scope) do
    if Scope.organization_selected?(scope), do: ~p"/dashboard", else: ~p"/organizations/select"
  end

  def signed_in_path(_), do: ~p"/"

  @doc """
  Plug for routes that should only be shown to unauthenticated users.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Plug for routes that require the user to be authenticated.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  @doc """
  Plug for routes that require an active organization in addition to authentication.
  """
  def require_active_organization(conn, _opts) do
    if Scope.organization_selected?(conn.assigns.current_scope) do
      conn
    else
      conn
      |> put_flash(:error, active_organization_required_message(conn.assigns.current_scope))
      |> maybe_store_organization_return_to()
      |> redirect(to: ~p"/organizations/select")
      |> halt()
    end
  end

  defp active_organization_required_message(%Scope{user: %Users.User{} = user}) do
    if Organizations.count_organizations(user) == 0 do
      "Create an organization to continue."
    else
      "Choose an organization to continue."
    end
  end

  defp active_organization_required_message(_scope), do: "Choose an organization to continue."

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp maybe_store_organization_return_to(%{method: "GET"} = conn) do
    put_session(conn, @organization_return_to_session_key, current_path(conn))
  end

  defp maybe_store_organization_return_to(conn), do: conn
end
