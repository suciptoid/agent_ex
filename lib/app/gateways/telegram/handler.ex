defmodule App.Gateways.Telegram.Handler do
  @moduledoc """
  Handles incoming Telegram webhook updates for a gateway.

  Parses Telegram Update objects, creates channels on first contact,
  routes messages to ChatRoom, and relays agent replies back.
  """

  require Logger

  alias App.Gateways
  alias App.Gateways.{Channel, Gateway}
  alias App.Gateways.Telegram.Client
  alias App.Chat

  @doc """
  Handles a Telegram update for the given gateway.
  Called by the webhook controller after secret verification.
  """
  def handle_update(%Gateway{} = gateway, %{"message" => message}) do
    handle_message(gateway, message)
  end

  def handle_update(%Gateway{} = gateway, %{"callback_query" => callback_query}) do
    handle_callback_query(gateway, callback_query)
  end

  def handle_update(_gateway, _update), do: :ok

  # --- Message handling ---

  defp handle_message(%Gateway{} = gateway, %{"chat" => %{"id" => chat_id}} = message) do
    text = Map.get(message, "text", "")
    from = Map.get(message, "from", %{})
    user_id = Map.get(from, "id")
    username = display_name(from)

    case text |> String.trim() do
      "/start" ->
        handle_start(gateway, chat_id, user_id, username)

      "" ->
        :ok

      content ->
        handle_user_message(gateway, chat_id, user_id, username, content)
    end
  end

  defp handle_message(_gateway, _message), do: :ok

  defp handle_start(%Gateway{} = gateway, chat_id, user_id, username) do
    if Gateways.user_allowed?(gateway, to_string(user_id)) do
      # Ensure channel exists
      {:ok, _channel} =
        Gateways.find_or_create_channel(gateway, %{
          external_chat_id: chat_id,
          external_user_id: user_id,
          external_username: username
        })

      client = Client.new(gateway.token)
      config = gateway.config || %{}
      welcome = config_value(config, :welcome_message, "Welcome! You're now connected.")
      Client.send_message(client, chat_id, welcome)
    else
      client = Client.new(gateway.token)
      Client.send_message(client, chat_id, "Sorry, you're not authorized to use this bot.")
    end
  end

  defp handle_user_message(%Gateway{} = gateway, chat_id, user_id, username, content) do
    unless Gateways.user_allowed?(gateway, to_string(user_id)) do
      :ok
    else
      case Gateways.find_or_create_channel(gateway, %{
             external_chat_id: chat_id,
             external_user_id: user_id,
             external_username: username
           }) do
        {:ok, %Channel{chat_room: chat_room} = channel} when not is_nil(chat_room) ->
          send_to_chat_room(gateway, channel, content)

        {:ok, _channel} ->
          Logger.warning("Channel created without chat_room for gateway #{gateway.id}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to find/create channel: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp send_to_chat_room(%Gateway{} = gateway, %Channel{} = channel, content) do
    chat_room = channel.chat_room

    # Create user message in the chat room
    case Chat.create_message(chat_room, %{
           role: "user",
           content: content,
           name: channel.external_username || "User"
         }) do
      {:ok, message} ->
        # Subscribe to chat room to relay agent responses back
        maybe_start_agent_and_relay(gateway, channel, chat_room, message)

      {:error, reason} ->
        Logger.error("Failed to create message: #{inspect(reason)}")
        :ok
    end
  end

  defp maybe_start_agent_and_relay(
         %Gateway{} = gateway,
         %Channel{} = channel,
         chat_room,
         _user_message
       ) do
    # Load chat room with agents
    chat_room =
      App.Repo.preload(chat_room, [:chat_room_agents, :agents, messages: [:agent, :tool_messages]])

    active_agent =
      case Enum.find(chat_room.chat_room_agents, & &1.is_active) do
        nil -> nil
        cra -> App.Repo.preload(cra, agent: :provider).agent
      end

    if active_agent do
      # Create a pending assistant message
      case Chat.create_message(chat_room, %{
             role: "assistant",
             content: nil,
             status: :pending,
             agent_id: active_agent.id
           }) do
        {:ok, assistant_message} ->
          # Start streaming and set up relay
          messages = Chat.list_messages(chat_room)
          Task.start(fn -> relay_response(gateway, channel, chat_room, assistant_message) end)
          Chat.start_stream(chat_room, messages, assistant_message)

        {:error, reason} ->
          Logger.error("Failed to create assistant message: #{inspect(reason)}")
      end
    else
      client = Client.new(gateway.token)

      Client.send_message(
        client,
        channel.external_chat_id,
        "No agent is configured for this conversation."
      )
    end
  end

  @doc """
  Subscribes to ChatRoom broadcasts and relays completed assistant messages
  back to the Telegram chat.
  """
  def relay_response(%Gateway{} = gateway, %Channel{} = channel, chat_room, %{id: message_id}) do
    Chat.subscribe_chat_room(chat_room)

    receive_loop(gateway, channel, message_id)
  end

  defp receive_loop(gateway, channel, message_id) do
    receive do
      {:stream_complete, ^message_id, _content} ->
        # Fetch the final message from DB
        case Chat.get_message_by_id(message_id) do
          %{content: content} when is_binary(content) and content != "" ->
            client = Client.new(gateway.token)
            Client.send_message(client, channel.external_chat_id, content)

          _ ->
            :ok
        end

      {:stream_error, ^message_id, _reason} ->
        client = Client.new(gateway.token)

        Client.send_message(
          client,
          channel.external_chat_id,
          "Sorry, an error occurred while processing your message."
        )

      _other ->
        receive_loop(gateway, channel, message_id)
    after
      120_000 ->
        Logger.warning("Relay timeout for message #{message_id}")
    end
  end

  # --- Callback query handling ---

  defp handle_callback_query(%Gateway{} = gateway, %{"id" => id} = _callback_query) do
    client = Client.new(gateway.token)
    Client.answer_callback_query(client, id)
  end

  defp handle_callback_query(_gateway, _callback_query), do: :ok

  # --- Helpers ---

  defp display_name(%{"first_name" => first, "last_name" => last}), do: "#{first} #{last}"
  defp display_name(%{"first_name" => first}), do: first
  defp display_name(%{"username" => username}), do: username
  defp display_name(_), do: nil

  defp config_value(%Gateway.Config{} = config, key, _default) do
    Map.get(config, key)
  end

  defp config_value(%{} = config, key, default) do
    Map.get(config, key, Map.get(config, to_string(key), default))
  end

  defp config_value(_, _key, default), do: default
end
