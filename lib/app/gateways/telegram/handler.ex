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

    case telegram_command(text) do
      :start ->
        handle_start(gateway, chat_id, user_id, username)

      :new ->
        handle_new(gateway, chat_id, user_id, username)

      :blank ->
        :ok

      :message ->
        handle_user_message(gateway, chat_id, user_id, username, String.trim(text))
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

  defp handle_new(%Gateway{} = gateway, chat_id, user_id, username) do
    client = Client.new(gateway.token)

    if Gateways.user_allowed?(gateway, to_string(user_id)) do
      case reset_or_create_channel(gateway, chat_id, user_id, username) do
        {:ok, _channel} ->
          config = gateway.config || %{}

          Client.send_message(
            client,
            chat_id,
            config_value(
              config,
              :new_chat_message,
              "Started a fresh chat. Send your next message when you're ready."
            )
          )

        {:error, reason} ->
          Logger.error("Failed to rotate Telegram channel chat room: #{inspect(reason)}")
          Client.send_message(client, chat_id, "Sorry, I couldn't start a new chat right now.")
      end
    else
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
    chat_room = Chat.preload_chat_room(chat_room)
    active_agent = active_agent(chat_room)

    if active_agent do
      # Create a pending assistant message
      case Chat.create_message(chat_room, %{
             role: "assistant",
             content: nil,
             status: :pending,
             agent_id: active_agent.id
           }) do
        {:ok, assistant_message} ->
          messages = chat_room.messages
          :ok = start_relay(gateway, channel, chat_room, assistant_message)

          Chat.start_stream(chat_room, messages, assistant_message,
            extra_system_prompt: telegram_reply_prompt()
          )

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

  defp receive_loop(gateway, channel, message_id) do
    receive do
      {:stream_complete, ^message_id, content} when is_binary(content) and content != "" ->
        client = Client.new(gateway.token)

        case Client.send_markdown_message(client, channel.external_chat_id, content) do
          {:ok, _response} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to send Telegram assistant reply: #{inspect(reason)}")
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

  defp telegram_command(text) do
    trimmed = String.trim(text || "")

    cond do
      trimmed == "" ->
        :blank

      Regex.match?(~r/^\/start(?:@[\w_]+)?(?:\s+.*)?$/u, trimmed) ->
        :start

      Regex.match?(~r/^\/new(?:@[\w_]+)?(?:\s+.*)?$/u, trimmed) ->
        :new

      true ->
        :message
    end
  end

  defp reset_or_create_channel(%Gateway{} = gateway, chat_id, user_id, username) do
    attrs = %{
      external_chat_id: chat_id,
      external_user_id: user_id,
      external_username: username
    }

    case Gateways.get_channel(gateway, chat_id) do
      nil ->
        Gateways.find_or_create_channel(gateway, attrs)

      %Channel{} = channel ->
        channel
        |> Map.put(:external_user_id, to_string(user_id))
        |> Map.put(:external_username, username)
        |> Gateways.reset_channel_chat_room()
    end
  end

  defp active_agent(%{chat_room_agents: chat_room_agents}) do
    case Enum.find(chat_room_agents, & &1.is_active) || List.first(chat_room_agents) do
      %{agent: agent} -> agent
      nil -> nil
    end
  end

  defp start_relay(gateway, channel, chat_room, assistant_message) do
    parent = self()
    ready_ref = make_ref()

    {:ok, _relay_pid} =
      Task.start(fn ->
        Chat.subscribe_chat_room(chat_room)
        typing_pid = start_typing_indicator(gateway, channel.external_chat_id)
        send(parent, {:gateway_relay_ready, ready_ref})

        try do
          receive_loop(gateway, channel, assistant_message.id)
        after
          stop_typing_indicator(typing_pid)
          Chat.unsubscribe_chat_room(chat_room)
        end
      end)

    receive do
      {:gateway_relay_ready, ^ready_ref} ->
        :ok
    after
      1_000 ->
        Logger.warning("Relay subscription setup timed out for message #{assistant_message.id}")
        :ok
    end
  end

  defp start_typing_indicator(%Gateway{} = gateway, chat_id) do
    client = Client.new(gateway.token)
    _ = Client.send_chat_action(client, chat_id)

    case Task.start(fn -> typing_loop(client, chat_id) end) do
      {:ok, pid} ->
        pid

      {:error, reason} ->
        Logger.warning("Failed to start Telegram typing indicator: #{inspect(reason)}")
        nil
    end
  end

  defp stop_typing_indicator(nil), do: :ok
  defp stop_typing_indicator(pid), do: send(pid, :stop)

  defp typing_loop(client, chat_id) do
    receive do
      :stop ->
        :ok
    after
      4_000 ->
        _ = Client.send_chat_action(client, chat_id)
        typing_loop(client, chat_id)
    end
  end

  defp telegram_reply_prompt do
    """
    When replying through Telegram, use Telegram-supported MarkdownV2 only.
    Do not use HTML formatting or unsupported Markdown features.
    Keep replies compatible with Telegram Bot API parse_mode=MarkdownV2.
    """
    |> String.trim()
  end

  defp config_value(%Gateway.Config{} = config, key, default) do
    Map.get(config, key) || default
  end

  defp config_value(%{} = config, key, default) do
    Map.get(config, key, Map.get(config, to_string(key), default))
  end

  defp config_value(_, _key, default), do: default
end
