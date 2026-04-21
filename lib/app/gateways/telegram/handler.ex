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

  defp handle_message(%Gateway{} = gateway, %{"chat" => %{"id" => _chat_id} = chat} = message) do
    text = Map.get(message, "text", "")
    context = telegram_context(chat, Map.get(message, "from", %{}))

    case telegram_command(text) do
      :start ->
        handle_start(gateway, context)

      :new ->
        handle_new(gateway, context)

      :blank ->
        :ok

      :message ->
        handle_user_message(gateway, context, String.trim(text))
    end
  end

  defp handle_message(_gateway, _message), do: :ok

  defp handle_start(%Gateway{} = gateway, context) do
    if Gateways.user_allowed?(gateway, sender_id(context)) do
      # Ensure channel exists
      {:ok, _channel} = Gateways.find_or_create_channel(gateway, channel_attrs(context))

      client = Client.new(gateway.token)
      config = gateway.config || %{}
      welcome = config_value(config, :welcome_message, "Welcome! You're now connected.")
      Client.send_message(client, context.chat_id, welcome)
    else
      client = Client.new(gateway.token)

      Client.send_message(
        client,
        context.chat_id,
        "Sorry, you're not authorized to use this bot."
      )
    end
  end

  defp handle_new(%Gateway{} = gateway, context) do
    client = Client.new(gateway.token)

    if Gateways.user_allowed?(gateway, sender_id(context)) do
      case reset_or_create_channel(gateway, context) do
        {:ok, _channel} ->
          config = gateway.config || %{}

          Client.send_message(
            client,
            context.chat_id,
            config_value(
              config,
              :new_chat_message,
              "Started a fresh chat. Send your next message when you're ready."
            )
          )

        {:error, reason} ->
          Logger.error("Failed to rotate Telegram channel chat room: #{inspect(reason)}")

          Client.send_message(
            client,
            context.chat_id,
            "Sorry, I couldn't start a new chat right now."
          )
      end
    else
      Client.send_message(
        client,
        context.chat_id,
        "Sorry, you're not authorized to use this bot."
      )
    end
  end

  defp handle_user_message(%Gateway{} = gateway, context, content) do
    unless Gateways.user_allowed?(gateway, sender_id(context)) do
      :ok
    else
      case Gateways.find_or_create_channel(gateway, channel_attrs(context)) do
        {:ok, %Channel{chat_room: chat_room} = channel} when not is_nil(chat_room) ->
          send_to_chat_room(gateway, channel, context.sender_name, content)

        {:ok, _channel} ->
          Logger.warning("Channel created without chat_room for gateway #{gateway.id}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to find/create channel: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp send_to_chat_room(%Gateway{} = gateway, %Channel{} = channel, sender_name, content) do
    chat_room = channel.chat_room

    # Create user message in the chat room
    case Chat.create_message(chat_room, %{
           role: "user",
           content: content,
           name: sender_name || channel.external_username || "User"
         }) do
      {:ok, message} ->
        Chat.broadcast_chat_room(chat_room.id, {:user_message_created, message})

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
          Chat.broadcast_chat_room(chat_room.id, {:agent_message_created, assistant_message})

          case Chat.start_stream(chat_room, messages, assistant_message,
                 extra_system_prompt: telegram_reply_prompt()
               ) do
            {:ok, stream_pid} ->
              :ok = start_relay(gateway, channel, chat_room, stream_pid)
              {:ok, stream_pid}

            {:error, reason} ->
              Logger.error("Failed to start Telegram chat stream: #{inspect(reason)}")
              :ok
          end

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

  defp receive_loop(gateway, channel, chat_room, stream_pid) do
    monitor_ref = Process.monitor(stream_pid)

    receive do
      {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
        relay_final_message(gateway, channel, chat_room)
    after
      120_000 ->
        Logger.warning("Relay timeout for Telegram chat room #{chat_room.id}")
        relay_timeout_message(gateway, channel)
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

  defp reset_or_create_channel(%Gateway{} = gateway, context) do
    attrs = channel_attrs(context)

    case Gateways.get_channel(gateway, context.chat_id) do
      nil ->
        Gateways.find_or_create_channel(gateway, attrs)

      %Channel{} ->
        with {:ok, channel} <- Gateways.find_or_create_channel(gateway, attrs) do
          Gateways.reset_channel_chat_room(channel)
        end
    end
  end

  defp active_agent(%{chat_room_agents: chat_room_agents}) do
    case Enum.find(chat_room_agents, & &1.is_active) || List.first(chat_room_agents) do
      %{agent: agent} -> agent
      nil -> nil
    end
  end

  defp start_relay(gateway, channel, chat_room, stream_pid) do
    client = Client.new(gateway.token)
    _ = Client.send_chat_action(client, channel.external_chat_id)

    {:ok, _relay_pid} =
      Task.start(fn ->
        typing_pid = start_typing_indicator(gateway, channel.external_chat_id)

        try do
          receive_loop(gateway, channel, chat_room, stream_pid)
        after
          stop_typing_indicator(typing_pid)
        end
      end)

    :ok
  end

  defp start_typing_indicator(%Gateway{} = gateway, chat_id) do
    client = Client.new(gateway.token)

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

  defp relay_final_message(gateway, channel, chat_room) do
    client = Client.new(gateway.token)

    case Chat.latest_assistant_message(chat_room) do
      %{status: :completed, content: content} when is_binary(content) and content != "" ->
        case Client.send_markdown_message(client, channel.external_chat_id, content) do
          {:ok, _response} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to send Telegram assistant reply: #{inspect(reason)}")
        end

      %{status: :completed} ->
        Client.send_message(
          client,
          channel.external_chat_id,
          "The agent finished without a reply."
        )

      _message ->
        Client.send_message(
          client,
          channel.external_chat_id,
          "Sorry, an error occurred while processing your message."
        )
    end
  end

  defp relay_timeout_message(gateway, channel) do
    client = Client.new(gateway.token)

    Client.send_message(
      client,
      channel.external_chat_id,
      "Sorry, the response took too long."
    )
  end

  defp telegram_reply_prompt do
    """
    You are replying through Telegram. Use only Telegram Bot API MarkdownV2.
    Allowed formatting from Telegram docs:
    - *bold text*
    - _italic text_
    - __underline__
    - ~strikethrough~
    - ||spoiler||
    - `inline code`
    - fenced code blocks with triple backticks
    - blockquotes using lines that start with >

    Important Telegram MarkdownV2 rules:
    - Never use HTML.
    - Never use GitHub/CommonMark tables, pipe-delimited columns, or markdown separators like |---|.
    - Never use GitHub-style bold like **bold**; use *bold* instead.
    - Prefer simple formatting. Use bullet lines starting with the literal bullet character •, not markdown list syntax.
    - If content is structured or tabular, rewrite it as short bullet points or Label: value lines.
    - Outside supported formatting entities, Telegram requires these characters to be escaped: _ * [ ] ( ) ~ ` > # + - = | { } . !
    - If a format is not explicitly supported by Telegram MarkdownV2, use plain text instead.
    """
    |> String.trim()
  end

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

  defp telegram_context(chat, from) do
    sender_name = display_name(from) || display_name(chat)

    %{
      chat_id: Map.get(chat, "id"),
      sender_id: Map.get(from, "id"),
      sender_name: sender_name,
      channel_name: channel_name(chat, sender_name),
      metadata: chat_metadata(chat)
    }
  end

  defp channel_name(%{"type" => "private"}, sender_name)
       when is_binary(sender_name) and sender_name != "",
       do: sender_name

  defp channel_name(%{"title" => title}, _sender_name) when is_binary(title) and title != "",
    do: title

  defp channel_name(%{"username" => username}, _sender_name)
       when is_binary(username) and username != "",
       do: username

  defp channel_name(%{"id" => _chat_id}, sender_name)
       when is_binary(sender_name) and sender_name != "",
       do: sender_name

  defp channel_name(%{"id" => chat_id}, _sender_name), do: "Chat #{chat_id}"

  defp chat_metadata(chat) do
    %{}
    |> put_metadata("chat_type", Map.get(chat, "type"))
    |> put_metadata("chat_title", Map.get(chat, "title"))
    |> put_metadata("chat_username", Map.get(chat, "username"))
  end

  defp channel_attrs(context) do
    %{
      external_chat_id: context.chat_id,
      external_user_id: context.sender_id,
      external_username: context.channel_name,
      metadata: context.metadata
    }
  end

  defp sender_id(%{sender_id: nil}), do: nil
  defp sender_id(%{sender_id: sender_id}), do: to_string(sender_id)

  defp put_metadata(metadata, _key, nil), do: metadata
  defp put_metadata(metadata, key, value), do: Map.put(metadata, key, value)
end
