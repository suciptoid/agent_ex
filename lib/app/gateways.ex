defmodule App.Gateways do
  @moduledoc """
  The Gateways context for managing external messaging platform integrations.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias App.Agents.Agent
  alias App.Chat.ChatRoom
  alias App.Gateways.{Channel, Gateway}
  alias App.Organizations
  alias App.Repo
  alias App.Users.Scope

  # --- Gateway CRUD ---

  def list_gateways(%Scope{} = scope) do
    Gateway
    |> where([g], g.organization_id == ^Scope.organization_id!(scope))
    |> order_by([g], desc: g.inserted_at)
    |> Repo.all()
  end

  def get_gateway!(%Scope{} = scope, id) do
    Repo.get_by!(Gateway, id: id, organization_id: Scope.organization_id!(scope))
  end

  def get_gateway(%Scope{} = scope, id) do
    Repo.get_by(Gateway, id: id, organization_id: Scope.organization_id!(scope))
  end

  def get_gateway_by_id(id) do
    Repo.get(Gateway, id)
  end

  def create_gateway(%Scope{} = scope, attrs) do
    %Gateway{organization_id: Scope.organization_id!(scope)}
    |> Gateway.changeset(attrs)
    |> validate_gateway_agents(scope)
    |> Repo.insert()
  end

  def update_gateway(%Scope{} = scope, %Gateway{} = gateway, attrs) do
    ensure_organization_owns!(scope, gateway)

    gateway
    |> Gateway.changeset(attrs)
    |> validate_gateway_agents(scope)
    |> Repo.update()
  end

  def delete_gateway(%Scope{} = scope, %Gateway{} = gateway) do
    ensure_organization_owns!(scope, gateway)
    Repo.delete(gateway)
  end

  def change_gateway(%Gateway{} = gateway, attrs \\ %{}) do
    Gateway.changeset(gateway, attrs)
  end

  # --- Channel operations ---

  def list_channels(%Gateway{} = gateway) do
    Channel
    |> where([c], c.gateway_id == ^gateway.id)
    |> order_by([c], desc: c.updated_at)
    |> preload([:chat_room])
    |> Repo.all()
  end

  def get_channel(%Gateway{} = gateway, external_chat_id) do
    Repo.get_by(Channel, gateway_id: gateway.id, external_chat_id: to_string(external_chat_id))
  end

  def get_channel_by_id(id) do
    Channel
    |> preload([:gateway, :chat_room])
    |> Repo.get(id)
  end

  def get_channel_by_chat_room_id(chat_room_id) do
    Channel
    |> preload([:gateway, :chat_room])
    |> Repo.get_by(chat_room_id: chat_room_id)
  end

  @doc """
  Finds an existing channel or creates a new one with an associated ChatRoom.
  Returns `{:ok, channel}` or `{:error, reason}`.

  When the external user is not mapped to an app user, the channel is created
  with `approval_status: :pending_approval`. Otherwise it defaults to `:approved`.
  """
  def find_or_create_channel(%Gateway{} = gateway, attrs) do
    external_chat_id = to_string(attrs[:external_chat_id] || attrs["external_chat_id"])

    case get_channel(gateway, external_chat_id) do
      %Channel{} = channel ->
        channel
        |> Repo.preload([:chat_room, :gateway])
        |> sync_existing_channel(attrs)
        |> then(fn
          {:ok, channel} -> ensure_channel_chat_room(channel)
          {:error, _reason} = error -> error
        end)

      nil ->
        approval_status = determine_approval_status(gateway, attrs)
        create_channel_with_chat_room(gateway, attrs, approval_status)
    end
  end

  def reset_channel_chat_room(%Channel{} = channel) do
    channel = Repo.preload(channel, [:chat_room, :gateway])

    case channel.gateway do
      %Gateway{} = gateway ->
        Multi.new()
        |> gateway_chat_room_multi(gateway, channel.external_username, channel.external_chat_id)
        |> Multi.update(:channel, fn %{chat_room: chat_room} ->
          Channel.changeset(channel, %{chat_room_id: chat_room.id})
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{channel: updated_channel}} ->
            {:ok, Repo.preload(updated_channel, [:chat_room, :gateway])}

          {:error, _step, changeset, _changes} ->
            {:error, changeset}
        end

      nil ->
        {:error, :missing_gateway}
    end
  end

  @doc """
  Checks whether an external user is allowed to create a channel on this gateway.
  """
  def user_allowed?(%Gateway{} = gateway, external_user_id) do
    config = gateway.config || %{}

    cond do
      config_value(config, :allow_all_users, true) ->
        true

      external_user_id in (config_value(config, :allowed_user_ids, []) |> Enum.map(&to_string/1)) ->
        true

      true ->
        false
    end
  end

  @doc """
  Checks if a channel requires approval (pending_approval status).
  """
  def channel_pending_approval?(%Channel{approval_status: :pending_approval}), do: true
  def channel_pending_approval?(%Channel{}), do: false

  @doc """
  Approves a pending channel and maps the external user to the given app user.
  """
  def approve_channel(%Scope{} = scope, %Channel{} = channel, user_id) do
    channel = Repo.preload(channel, :gateway)

    with :ok <- validate_channel_mapping_user_id(user_id),
         {:ok, _secret} <- put_channel_user_mapping(scope, channel, user_id),
         {:ok, channel} <-
           channel
           |> Channel.changeset(%{approval_status: :approved})
           |> Repo.update(),
         {_count, nil} <- backfill_channel_message_user_ids(channel, user_id) do
      {:ok, Repo.preload(channel, [:chat_room, :gateway])}
    end
  end

  @doc """
  Rejects a pending channel.
  """
  def reject_channel(%Channel{} = channel) do
    channel
    |> Channel.changeset(%{approval_status: :rejected, status: :blocked})
    |> Repo.update()
  end

  @doc """
  Returns the mapped app user_id for a given gateway type + external_user_id,
  or nil if no mapping exists.
  """
  def get_mapped_user_id(%Scope{} = scope, gateway_type, external_user_id)
      when is_atom(gateway_type) and is_binary(external_user_id) do
    key = channel_user_mapping_key(gateway_type, external_user_id)
    Organizations.get_secret_value(scope, key)
  end

  @doc """
  Resolves the mapped app user_id for a channel, or nil when the channel is not mapped.
  """
  def mapped_user_id_for_channel(%Channel{} = channel) do
    gateway = channel.gateway || Repo.preload(channel, :gateway).gateway

    with %Gateway{} = gateway <- gateway,
         external_user_id when is_binary(external_user_id) and external_user_id != "" <-
           channel.external_user_id do
      scope = scope_for_gateway(gateway)
      get_mapped_user_id(scope, gateway.type, external_user_id)
    else
      _other -> nil
    end
  end

  @doc """
  Stores a channel user mapping: gateway_type + external_user_id -> app_user_id.
  """
  def put_channel_user_mapping(%Scope{} = scope, %Channel{} = channel, user_id) do
    gateway = channel.gateway || Repo.preload(channel, :gateway).gateway
    key = channel_user_mapping_key(gateway.type, channel.external_user_id)
    Organizations.get_secret(scope, key) || %App.Organizations.Secret{}

    cond do
      is_nil(user_id) or user_id == "" ->
        {:ok, nil}

      true ->
        Organizations.put_secret_value(scope, key, user_id)
    end
  end

  @doc """
  Lists all channel user mappings for the current organization.
  Returns a list of `%{gateway_type: atom, external_user_id: string, user_id: string, key: string}`.
  """
  def list_channel_user_mappings(%Scope{} = scope) do
    import Ecto.Query

    prefix = "channel_user_map:"

    from(s in App.Organizations.Secret,
      where: s.organization_id == ^Scope.organization_id!(scope) and like(s.key, ^"#{prefix}%"),
      select: %{key: s.key, value: s.value}
    )
    |> Repo.all()
    |> Enum.map(fn %{key: key, value: user_id} ->
      case String.split(String.replace_prefix(key, prefix, ""), ":", parts: 2) do
        [gateway_type, external_user_id] ->
          %{
            gateway_type: gateway_type,
            external_user_id: external_user_id,
            user_id: user_id,
            key: key
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Deletes a channel user mapping by key.
  """
  def delete_channel_user_mapping(%Scope{} = scope, key) when is_binary(key) do
    case Organizations.get_secret(scope, key) do
      nil -> {:error, :not_found}
      secret -> Repo.delete(secret)
    end
  end

  defp validate_channel_mapping_user_id(user_id) when is_binary(user_id) do
    if String.trim(user_id) == "" do
      {:error, :user_id_required}
    else
      :ok
    end
  end

  defp validate_channel_mapping_user_id(_user_id), do: {:error, :user_id_required}

  defp backfill_channel_message_user_ids(%Channel{chat_room_id: chat_room_id}, user_id) do
    import Ecto.Query

    from(message in App.Chat.Message,
      where:
        message.chat_room_id == ^chat_room_id and
          message.role == "user" and
          is_nil(message.user_id)
    )
    |> Repo.update_all(set: [user_id: user_id])
  end

  defp channel_user_mapping_key(gateway_type, external_user_id) do
    "channel_user_map:#{gateway_type}:#{external_user_id}"
  end

  # --- Private ---

  defp create_channel_with_chat_room(%Gateway{} = gateway, attrs, approval_status) do
    external_chat_id = to_string(attrs[:external_chat_id] || attrs["external_chat_id"])
    external_user_id = attrs[:external_user_id] || attrs["external_user_id"]
    external_username = attrs[:external_username] || attrs["external_username"]
    metadata = attrs[:metadata] || attrs["metadata"] || %{}

    Multi.new()
    |> gateway_chat_room_multi(gateway, external_username, external_chat_id)
    |> Multi.insert(:channel, fn %{chat_room: chat_room} ->
      %Channel{gateway_id: gateway.id}
      |> Channel.changeset(%{
        external_chat_id: external_chat_id,
        external_user_id: external_user_id && to_string(external_user_id),
        external_username: external_username,
        metadata: metadata,
        chat_room_id: chat_room.id,
        approval_status: approval_status
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{channel: channel}} ->
        {:ok, Repo.preload(channel, [:chat_room, :gateway])}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp determine_approval_status(%Gateway{} = gateway, attrs) do
    external_user_id = attrs[:external_user_id] || attrs["external_user_id"]

    if is_nil(external_user_id) or external_user_id == "" do
      :pending_approval
    else
      scope = scope_for_gateway(gateway)

      case get_mapped_user_id(scope, gateway.type, to_string(external_user_id)) do
        user_id when is_binary(user_id) and user_id != "" -> :approved
        _ -> :pending_approval
      end
    end
  end

  defp scope_for_gateway(%Gateway{organization_id: org_id}) do
    org = Repo.get(App.Organizations.Organization, org_id) || %{id: org_id}
    %Scope{user: nil, organization: org, organization_role: "admin"}
  end

  defp ensure_channel_chat_room(%Channel{chat_room_id: nil} = channel),
    do: reset_channel_chat_room(channel)

  defp ensure_channel_chat_room(%Channel{} = channel), do: {:ok, channel}

  defp sync_existing_channel(%Channel{} = channel, attrs) do
    with {:ok, channel} <- maybe_update_channel_identity(channel, attrs),
         {:ok, channel} <- maybe_update_chat_room_title(channel) do
      {:ok, channel}
    end
  end

  defp maybe_update_channel_identity(%Channel{} = channel, attrs) do
    external_user_id = attrs[:external_user_id] || attrs["external_user_id"]
    external_username = attrs[:external_username] || attrs["external_username"]

    merged_metadata =
      merge_channel_metadata(channel.metadata, attrs[:metadata] || attrs["metadata"])

    changes =
      %{}
      |> maybe_put_channel_change(
        :external_user_id,
        stringify_value(external_user_id),
        channel.external_user_id
      )
      |> maybe_put_channel_change(
        :external_username,
        external_username,
        channel.external_username
      )
      |> maybe_put_channel_change(:metadata, merged_metadata, channel.metadata || %{})

    if map_size(changes) == 0 do
      {:ok, channel}
    else
      case channel |> Channel.changeset(changes) |> Repo.update() do
        {:ok, channel} ->
          {:ok, Repo.preload(channel, [:chat_room, :gateway])}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp maybe_update_chat_room_title(%Channel{chat_room: %ChatRoom{} = chat_room} = channel) do
    title = channel_title(channel.external_username, channel.external_chat_id)

    if title in [nil, "", chat_room.title] do
      {:ok, channel}
    else
      case chat_room |> ChatRoom.changeset(%{title: title}) |> Repo.update() do
        {:ok, chat_room} ->
          {:ok, %{channel | chat_room: chat_room, chat_room_id: chat_room.id}}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp maybe_update_chat_room_title(%Channel{} = channel), do: {:ok, channel}

  defp gateway_chat_room_multi(multi, %Gateway{} = gateway, external_username, external_chat_id) do
    title = channel_title(external_username, external_chat_id)
    agent_ids = gateway_agent_ids(gateway.config || %{})
    default_agent_id = gateway_default_agent_id(gateway.config || %{})

    multi
    |> Multi.insert(:chat_room, fn _changes ->
      %ChatRoom{organization_id: gateway.organization_id}
      |> ChatRoom.changeset(%{title: title})
    end)
    |> Multi.run(:chat_room_agents, fn repo, %{chat_room: chat_room} ->
      insert_gateway_chat_room_agents(
        repo,
        chat_room,
        gateway.organization_id,
        agent_ids,
        default_agent_id
      )
    end)
  end

  defp insert_gateway_chat_room_agents(
         _repo,
         _chat_room,
         _organization_id,
         [],
         _default_agent_id
       ),
       do: {:ok, []}

  defp insert_gateway_chat_room_agents(
         repo,
         chat_room,
         organization_id,
         agent_ids,
         default_agent_id
       ) do
    agents =
      from(agent in Agent,
        where: agent.organization_id == ^organization_id and agent.id in ^agent_ids
      )
      |> repo.all()
      |> Enum.sort_by(fn agent -> Enum.find_index(agent_ids, &(&1 == agent.id)) end)

    active_agent_id =
      cond do
        default_agent_id in Enum.map(agents, & &1.id) -> default_agent_id
        agents == [] -> nil
        true -> List.first(agents).id
      end

    Enum.reduce_while(agents, {:ok, []}, fn agent, {:ok, chat_room_agents} ->
      case %App.Chat.ChatRoomAgent{}
           |> App.Chat.ChatRoomAgent.changeset(%{
             chat_room_id: chat_room.id,
             agent_id: agent.id,
             is_active: agent.id == active_agent_id
           })
           |> repo.insert() do
        {:ok, chat_room_agent} ->
          {:cont, {:ok, [chat_room_agent | chat_room_agents]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, chat_room_agents} -> {:ok, Enum.reverse(chat_room_agents)}
      {:error, _reason} = error -> error
    end
  end

  defp gateway_agent_ids(config) do
    config_value(config, :agent_ids, [])
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp gateway_default_agent_id(config), do: config_value(config, :agent_id, nil)

  defp channel_title(nil, external_chat_id), do: "Chat #{external_chat_id}"
  defp channel_title("", external_chat_id), do: "Chat #{external_chat_id}"
  defp channel_title(username, _external_chat_id), do: username

  defp config_value(%Gateway.Config{} = config, key, default) do
    case Map.get(config, key) do
      nil -> default
      value -> value
    end
  end

  defp config_value(%{} = config, key, default) do
    Map.get(config, key, Map.get(config, to_string(key), default))
  end

  defp config_value(_, _key, default), do: default

  defp merge_channel_metadata(current_metadata, new_metadata) when is_map(new_metadata) do
    current_metadata
    |> normalize_metadata()
    |> Map.merge(new_metadata)
  end

  defp merge_channel_metadata(current_metadata, _new_metadata),
    do: normalize_metadata(current_metadata)

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp maybe_put_channel_change(changes, _field, nil, _current), do: changes

  defp maybe_put_channel_change(changes, field, value, current) when value != current do
    Map.put(changes, field, value)
  end

  defp maybe_put_channel_change(changes, _field, _value, _current), do: changes

  defp stringify_value(nil), do: nil
  defp stringify_value(value), do: to_string(value)

  defp ensure_organization_owns!(%Scope{} = scope, %Gateway{organization_id: org_id}) do
    if org_id != Scope.organization_id!(scope) do
      raise Ecto.NoResultsError, query: Gateway
    end
  end

  defp validate_gateway_agents(changeset, %Scope{} = scope) do
    config = Ecto.Changeset.get_field(changeset, :config)
    agent_ids = gateway_agent_ids(config || %{})
    default_agent_id = gateway_default_agent_id(config || %{})

    valid_agent_ids =
      from(agent in Agent,
        where: agent.organization_id == ^Scope.organization_id!(scope) and agent.id in ^agent_ids,
        select: agent.id
      )
      |> Repo.all()

    cond do
      length(valid_agent_ids) != length(agent_ids) ->
        Ecto.Changeset.add_error(
          changeset,
          :config,
          "assigned agents must belong to the current organization"
        )

      is_binary(default_agent_id) and default_agent_id not in valid_agent_ids ->
        Ecto.Changeset.add_error(
          changeset,
          :config,
          "default agent must be one of the assigned agents"
        )

      true ->
        changeset
    end
  end
end
