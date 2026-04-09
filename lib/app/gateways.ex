defmodule App.Gateways do
  @moduledoc """
  The Gateways context for managing external messaging platform integrations.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias App.Agents.Agent
  alias App.Chat.ChatRoom
  alias App.Gateways.{Channel, Gateway}
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
    |> Repo.insert()
  end

  def update_gateway(%Scope{} = scope, %Gateway{} = gateway, attrs) do
    ensure_organization_owns!(scope, gateway)

    gateway
    |> Gateway.changeset(attrs)
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

  @doc """
  Finds an existing channel or creates a new one with an associated ChatRoom.
  Returns `{:ok, channel}` or `{:error, reason}`.
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
        create_channel_with_chat_room(gateway, attrs)
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

  # --- Private ---

  defp create_channel_with_chat_room(%Gateway{} = gateway, attrs) do
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
        chat_room_id: chat_room.id
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
    agent_id = gateway_agent_id(gateway.config || %{})

    multi
    |> Multi.insert(:chat_room, fn _changes ->
      %ChatRoom{organization_id: gateway.organization_id}
      |> ChatRoom.changeset(%{title: title})
    end)
    |> Multi.run(:chat_room_agent, fn repo, %{chat_room: chat_room} ->
      maybe_insert_gateway_chat_room_agent(repo, chat_room, agent_id)
    end)
  end

  defp maybe_insert_gateway_chat_room_agent(_repo, _chat_room, nil), do: {:ok, nil}

  defp maybe_insert_gateway_chat_room_agent(repo, chat_room, agent_id) do
    case repo.get(Agent, agent_id) do
      nil ->
        {:ok, nil}

      _agent ->
        %App.Chat.ChatRoomAgent{}
        |> App.Chat.ChatRoomAgent.changeset(%{
          chat_room_id: chat_room.id,
          agent_id: agent_id,
          is_active: true
        })
        |> repo.insert()
    end
  end

  defp gateway_agent_id(config), do: config_value(config, :agent_id, nil)

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
end
