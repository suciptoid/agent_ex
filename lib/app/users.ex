defmodule App.Users do
  @moduledoc """
  The Users context.
  """

  import Ecto.Query, warn: false
  alias App.Repo

  alias App.Users.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a user by Google subject identifier.
  """
  def get_user_by_google_id(google_id) when is_binary(google_id) do
    Repo.get_by(User, google_id: google_id)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for password-based registration.
  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  ## Settings

  def change_user_name(user, attrs \\ %{}) do
    User.name_changeset(user, attrs)
  end

  def update_user_name(user, attrs) do
    user
    |> User.name_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `App.Users.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `App.Users.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Returns true when Google OAuth credentials are configured.
  """
  def google_auth_enabled? do
    oauth_config = Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])

    google_oauth_value_present?(oauth_config[:client_id]) and
      google_oauth_value_present?(oauth_config[:client_secret])
  end

  @doc """
  Finds or creates a user for a verified Google account.
  """
  def get_or_register_user_by_google(
        %{
          google_id: google_id,
          email: email,
          email_verified?: email_verified?
        } = attrs
      )
      when is_binary(google_id) do
    name = Map.get(attrs, :name)

    cond do
      not email_verified? ->
        {:error, :email_not_verified}

      not valid_google_email?(email) ->
        {:error, :email_missing}

      user = get_user_by_google_id(google_id) ->
        maybe_confirm_google_user(user, google_id, name)

      user = get_user_by_email(email) ->
        link_google_user(user, google_id, email, name)

      true ->
        create_google_user(google_id, email, name)
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc """
  Delivers reset password instructions to the given user.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")

    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  Returns `nil` if the token is invalid or expired.
  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user's password.
  """
  def reset_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  defp create_google_user(google_id, email, name) do
    %User{}
    |> User.google_changeset(%{
      email: email,
      google_id: google_id,
      name: name,
      confirmed_at: DateTime.utc_now(:second)
    })
    |> Repo.insert()
  end

  defp link_google_user(%User{google_id: nil} = user, google_id, email, name) do
    attrs = %{
      email: email,
      google_id: google_id,
      confirmed_at: user.confirmed_at || DateTime.utc_now(:second)
    }

    attrs = if name && user.name in [nil, ""], do: Map.put(attrs, :name, name), else: attrs

    user
    |> User.google_changeset(attrs)
    |> Repo.update()
  end

  defp link_google_user(%User{google_id: google_id} = user, google_id, _email, name) do
    maybe_confirm_google_user(user, google_id, name)
  end

  defp link_google_user(%User{}, _google_id, _email, _name),
    do: {:error, :google_account_conflict}

  defp maybe_confirm_google_user(%User{confirmed_at: nil} = user, google_id, name) do
    attrs = %{
      email: user.email,
      google_id: google_id,
      confirmed_at: DateTime.utc_now(:second)
    }

    attrs = if name && user.name in [nil, ""], do: Map.put(attrs, :name, name), else: attrs

    user
    |> User.google_changeset(attrs)
    |> Repo.update()
  end

  defp maybe_confirm_google_user(%User{} = user, _google_id, _name), do: {:ok, user}

  defp valid_google_email?(email) when is_binary(email), do: String.trim(email) != ""
  defp valid_google_email?(_email), do: false

  defp google_oauth_value_present?({System, :get_env, [env_var]}) do
    google_oauth_value_present?(System.get_env(env_var))
  end

  defp google_oauth_value_present?(value) when is_binary(value), do: String.trim(value) != ""
  defp google_oauth_value_present?(_value), do: false
end
