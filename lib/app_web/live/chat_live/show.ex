defmodule AppWeb.ChatLive.Show do
  use AppWeb, :live_view

  alias App.Chat
  alias App.Chat.Message

  @hidden_tool_names [
    "update_chatroom_title"
  ]

  @impl true
  def mount(_params, _session, socket) do
    available_agents = App.Agents.list_agents(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:chat_room, nil)
     |> assign(:available_agents, available_agents)
     |> assign(:agent_message_streams, %{})
     |> assign(:latest_message_id, nil)
     |> assign(:messages_revision, 0)
     |> assign(:streaming_message_id, nil)
     |> assign(:streaming_message_agent, nil)
     |> assign(:streaming_message_inserted_at, nil)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_thinking, nil)
     |> assign(:streaming_tool_calls, [])
     |> assign(:streaming_tool_responses, [])
     |> assign(:streaming_token_count, 0)
     |> assign(:streaming_active?, false)
     |> assign(:subscribed_chat_room_id, nil)
     |> assign_message_form(%{"content" => ""})
     |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
     |> stream(:messages, [])}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    {:noreply, socket |> maybe_switch_subscription(id) |> load_chat_room(id)}
  end

  @impl true
  def handle_event("validate", %{"message" => message_params}, socket) do
    {:noreply, assign_message_form(socket, message_params)}
  end

  def handle_event("send", _params, %{assigns: %{streaming_active?: true}} = socket) do
    {:noreply, put_flash(socket, :error, "Wait for the current response to finish first")}
  end

  def handle_event("send", %{"message" => %{"content" => content} = message_params}, socket) do
    content = String.trim(content || "")

    if content == "" do
      {:noreply,
       socket
       |> assign_message_form(message_params)
       |> put_flash(:error, "Message cannot be blank")}
    else
      chat_room = socket.assigns.chat_room

      case Chat.create_message(chat_room, %{role: "user", content: content}) do
        {:ok, user_message} ->
          Chat.broadcast_chat_room_from(
            chat_room.id,
            self(),
            {:user_message_created, user_message}
          )

          messages = Chat.list_messages(chat_room)
          active_agent = active_agent_for_room(chat_room)

          case Chat.create_message(chat_room, %{
                 role: "assistant",
                 content: nil,
                 status: :pending,
                 agent_id: active_agent && active_agent.id,
                 metadata: %{}
               }) do
            {:ok, placeholder_message} ->
              case Chat.start_stream(
                     chat_room,
                     messages,
                     placeholder_message,
                     stream_run_opts(socket)
                   ) do
                {:ok, _pid} ->
                  Chat.broadcast_chat_room_from(
                    chat_room.id,
                    self(),
                    {:agent_message_created, placeholder_message}
                  )

                  {:noreply,
                   socket
                   |> begin_stream(placeholder_message)
                   |> assign_message_form(%{"content" => ""})
                   |> push_event("scroll-to-bottom", %{})}

                {:error, reason} ->
                  {:noreply,
                   socket
                   |> put_flash(:error, "Failed to start stream: #{user_error_message(reason)}")
                   |> load_chat_room(chat_room.id)}
              end

            {:error, _reason} ->
              {:noreply,
               socket
               |> assign_message_form(%{"content" => ""})
               |> put_flash(:error, "Failed to prepare assistant response")}
          end

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign_message_form(message_params)
           |> put_flash(:error, "Failed to send: #{changeset_error(changeset)}")}
      end
    end
  end

  def handle_event("regenerate", %{"id" => id}, socket) do
    chat_room = socket.assigns.chat_room
    messages = Chat.list_messages(chat_room)
    message = Enum.find(messages, &(&1.id == id))

    cond do
      socket.assigns.streaming_active? ->
        {:noreply, put_flash(socket, :error, "Wait for the current response to finish first")}

      is_nil(message) ->
        {:noreply, put_flash(socket, :error, "Message not found")}

      not regeneratable_message?(message, socket.assigns.latest_message_id) ->
        {:noreply,
         put_flash(socket, :error, "Only the latest assistant response can be regenerated")}

      true ->
        prior_messages = Enum.take_while(messages, &(&1.id != message.id))
        active_agent = active_agent_for_room(chat_room)
        agent_id = (active_agent && active_agent.id) || message.agent_id

        attrs =
          %{
            content: nil,
            status: :pending,
            metadata: reset_message_metadata(message.metadata)
          }
          |> maybe_put_agent_id(agent_id)

        case Chat.update_message(message, attrs) do
          {:ok, placeholder_message} ->
            case Chat.delete_tool_messages(placeholder_message) do
              {_count, nil} ->
                case Chat.start_stream(
                       chat_room,
                       prior_messages,
                       placeholder_message,
                       stream_run_opts(socket)
                     ) do
                  {:ok, _pid} ->
                    Chat.broadcast_chat_room_from(
                      chat_room.id,
                      self(),
                      {:stream_updated, placeholder_message}
                    )

                    {:noreply,
                     socket
                     |> begin_stream(placeholder_message)
                     |> push_event("scroll-to-bottom", %{})}

                  {:error, reason} ->
                    {:noreply,
                     put_flash(
                       socket,
                       :error,
                       "Failed to regenerate: #{user_error_message(reason)}"
                     )}
                end

              {_count, _rows} ->
                {:noreply, put_flash(socket, :error, "Failed to clear tool history")}
            end

          {:error, changeset} ->
            {:noreply,
             put_flash(socket, :error, "Failed to regenerate: #{changeset_error(changeset)}")}
        end
    end
  end

  def handle_event("cancel-stream", _params, %{assigns: %{streaming_message_id: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-stream", _params, socket) do
    case Chat.cancel_stream(socket.assigns.streaming_message_id) do
      :ok ->
        {:noreply,
         socket
         |> load_chat_room(socket.assigns.chat_room.id)
         |> put_flash(:info, "Stopped generating")}

      {:error, :not_found} ->
        {:noreply, socket |> load_chat_room(socket.assigns.chat_room.id) |> reset_main_stream()}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Failed to stop stream: #{user_error_message(reason)}")}
    end
  end

  def handle_event("set-active-agent", %{"id" => agent_id}, socket) do
    {:noreply, set_active_agent(socket, agent_id)}
  end

  def handle_event("add-agent-to-room", %{"id" => agent_id}, socket) do
    chat_room = socket.assigns.chat_room

    case Chat.add_agent_to_room(socket.assigns.current_scope, chat_room, agent_id) do
      {:ok, _} ->
        {:noreply, load_chat_room(socket, chat_room.id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to add agent")}
    end
  end

  def handle_event("remove-agent-from-room", %{"id" => agent_id}, socket) do
    chat_room = socket.assigns.chat_room

    case Chat.remove_agent_from_room(socket.assigns.current_scope, chat_room, agent_id) do
      {:ok, _} ->
        {:noreply, load_chat_room(socket, chat_room.id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to remove agent")}
    end
  end

  @impl true
  def handle_info(
        {:stream_chunk, message_id, token},
        %{assigns: %{streaming_message_id: message_id}} = socket
      ) do
    new_content = append_text(socket.assigns.streaming_content, token)

    {:noreply,
     socket
     |> assign(:streaming_content, new_content)
     |> assign(:streaming_token_count, socket.assigns.streaming_token_count + 1)
     |> assign(:streaming_active?, true)
     |> maybe_stream_main_placeholder()}
  end

  def handle_info({:stream_chunk, message_id, token}, socket),
    do: {:noreply, stream_agent_message_chunk(socket, message_id, token)}

  def handle_info(
        {:stream_thinking_chunk, message_id, token},
        %{assigns: %{streaming_message_id: message_id}} = socket
      ) do
    new_thinking = append_text(socket.assigns.streaming_thinking, token)

    {:noreply,
     socket
     |> assign(:streaming_thinking, new_thinking)
     |> assign(:streaming_active?, true)
     |> maybe_stream_main_placeholder()}
  end

  def handle_info({:stream_thinking_chunk, message_id, token}, socket),
    do: {:noreply, stream_agent_message_thinking_chunk(socket, message_id, token)}

  def handle_info(
        {:stream_tool_started, message_id, tool_result},
        %{assigns: %{streaming_message_id: message_id}} = socket
      ) do
    {:noreply, put_main_stream_tool_response(socket, tool_result)}
  end

  def handle_info({:stream_tool_started, message_id, tool_result}, socket) do
    {:noreply, put_agent_stream_tool_response(socket, message_id, tool_result)}
  end

  def handle_info(
        {:stream_tool_result, message_id, tool_result},
        %{assigns: %{streaming_message_id: message_id}} = socket
      ) do
    {:noreply, put_main_stream_tool_response(socket, tool_result)}
  end

  def handle_info({:stream_tool_result, message_id, tool_result}, socket) do
    {:noreply, put_agent_stream_tool_response(socket, message_id, tool_result)}
  end

  def handle_info({:agent_message_created, message}, socket) do
    if same_chat_room_message?(socket, message) do
      {:noreply, refresh_chat_messages(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:user_message_created, message}, socket) do
    if same_chat_room_message?(socket, message) do
      {:noreply, refresh_chat_messages(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:agent_message_stream_chunk, message_id, token}, socket) do
    {:noreply, stream_agent_message_chunk(socket, message_id, token)}
  end

  def handle_info({:agent_message_thinking_chunk, message_id, token}, socket) do
    {:noreply, stream_agent_message_thinking_chunk(socket, message_id, token)}
  end

  def handle_info({:agent_message_tool_started, message_id, tool_result}, socket) do
    {:noreply, put_agent_stream_tool_response(socket, message_id, tool_result)}
  end

  def handle_info({:agent_message_tool_result, message_id, tool_result}, socket) do
    {:noreply, put_agent_stream_tool_response(socket, message_id, tool_result)}
  end

  def handle_info({:agent_message_updated, message}, socket) do
    if same_chat_room_message?(socket, message) do
      {:noreply, socket |> clear_agent_stream(message.id) |> refresh_chat_messages()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:active_agent_changed, _agent_id}, socket) do
    {:noreply, load_chat_room(socket, socket.assigns.chat_room.id)}
  end

  def handle_info({:chatroom_title_updated, title}, socket) do
    chat_room = %{socket.assigns.chat_room | title: title}

    {:noreply,
     socket
     |> assign(:chat_room, chat_room)
     |> assign(:page_title, title)
     |> refresh_sidebar_chat_rooms()}
  end

  def handle_info({:stream_updated, message}, socket) do
    if same_chat_room_message?(socket, message) do
      {:noreply, socket |> clear_agent_stream(message.id) |> refresh_chat_messages()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stream_complete, _message_id, _content}, socket) do
    {:noreply, socket |> refresh_chat_messages() |> reset_main_stream()}
  end

  def handle_info({:stream_error, _message_id, _content}, socket) do
    {:noreply, socket |> refresh_chat_messages() |> reset_main_stream()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  def user_message?(message), do: message.role == "user"
  def assistant_message?(message), do: message.role == "assistant"
  def latest_message?(message, latest_message_id), do: message.id == latest_message_id
  def message_has_content?(message), do: (Map.get(message, :content) || "") != ""

  def delegated_message?(message) do
    metadata_value(message, "delegated") == true
  end

  def regeneratable_message?(nil, _latest_message_id), do: false

  def regeneratable_message?(message, latest_message_id) do
    assistant_message?(message) and
      not delegated_message?(message) and
      latest_message?(message, latest_message_id) and
      message.status in [:completed, :error] and
      not Chat.stream_running?(message.id)
  end

  def regenerate_label(%{status: :error}), do: "Retry"
  def regenerate_label(_message), do: "Regenerate"

  def streaming_message?(%{status: status}), do: status in [:pending, :streaming]

  def show_streaming_indicator?(message, streaming_message_id, agent_message_streams) do
    cond do
      not (assistant_message?(message) and streaming_message?(message)) ->
        false

      delegated_message?(message) ->
        delegated_stream_started?(message, agent_message_streams)

      message.id == streaming_message_id ->
        true

      true ->
        true
    end
  end

  def speaker_name(%{role: "user"}), do: "You"
  def speaker_name(%{role: "tool", name: name}) when is_binary(name) and name != "", do: name
  def speaker_name(%{agent: %{name: name}}), do: name
  def speaker_name(_message), do: "Assistant"

  def message_icon(%{role: "user"}), do: "hero-user"
  def message_icon(%{role: "assistant"}), do: "hero-cpu-chip"
  def message_icon(%{role: "system"}), do: "hero-command-line"
  def message_icon(%{role: "tool"}), do: "hero-wrench-screwdriver"
  def message_icon(_message), do: "hero-wrench-screwdriver"

  def message_thinking(%Message{} = message), do: Message.thinking(message)
  def message_thinking(message), do: metadata_value(message, "thinking")

  def tool_responses(%Message{} = message) do
    message
    |> Message.tool_responses()
    |> Enum.reject(&hidden_tool_response?/1)
  end

  def tool_responses(message) do
    message
    |> metadata_value("tool_responses")
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&hidden_tool_response?/1)
  end

  def tool_response_label(tool_response) do
    Map.get(tool_response, "name") || "tool"
  end

  def tool_response_error?(tool_response), do: Map.get(tool_response, "status") == "error"
  def tool_response_running?(tool_response), do: Map.get(tool_response, "status") == "running"

  def tool_response_content(tool_response) do
    case Map.get(tool_response, "content") do
      nil ->
        if tool_response_running?(tool_response), do: "Waiting for tool output…", else: ""

      content ->
        content
    end
  end

  def assistant_tool_calls(%Message{} = message) do
    message
    |> Message.tool_calls()
    |> Enum.reject(&hidden_tool_call?/1)
  end

  def assistant_tool_calls(message) do
    message
    |> metadata_value("tool_calls")
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&hidden_tool_call?/1)
  end

  def assistant_tool_entries(%Message{} = message) do
    do_assistant_tool_entries(message, include_orphan_responses?: true)
  end

  def assistant_tool_entries(message) do
    do_assistant_tool_entries(message, include_orphan_responses?: false)
  end

  defp do_assistant_tool_entries(message, opts) do
    tool_calls = assistant_tool_calls(message)
    tool_responses = tool_responses(message)

    {entries, used_response_ids} =
      Enum.map_reduce(tool_calls, MapSet.new(), fn tool_call, used_response_ids ->
        tool_call_id = tool_call_id(tool_call)
        tool_response = Enum.find(tool_responses, &(tool_response_id(&1) == tool_call_id))

        used_response_ids =
          if is_binary(tool_call_id) and tool_call_id != "" do
            MapSet.put(used_response_ids, tool_call_id)
          else
            used_response_ids
          end

        {%{tool_call: tool_call, tool_response: tool_response}, used_response_ids}
      end)

    extra_entries =
      if Keyword.get(opts, :include_orphan_responses?, false) do
        tool_responses
        |> Enum.reject(&(tool_response_id(&1) in used_response_ids))
        |> Enum.map(fn tool_response ->
          %{tool_call: nil, tool_response: tool_response}
        end)
      else
        []
      end

    entries ++ extra_entries
  end

  def tool_call_label(tool_call) do
    Map.get(tool_call, "name") || Map.get(tool_call, :name) || "tool"
  end

  def tool_entry_label(%{tool_response: tool_response}) when is_map(tool_response),
    do: tool_response_label(tool_response)

  def tool_entry_label(%{tool_call: tool_call}) when is_map(tool_call),
    do: tool_call_label(tool_call)

  def tool_entry_label(_tool_entry), do: "tool"

  def tool_entry_error?(%{tool_response: tool_response}) when is_map(tool_response),
    do: tool_response_error?(tool_response)

  def tool_entry_error?(_tool_entry), do: false

  def tool_entry_running?(%{tool_response: nil}), do: true

  def tool_entry_running?(%{tool_response: tool_response}) when is_map(tool_response),
    do: tool_response_running?(tool_response)

  def tool_entry_running?(_tool_entry), do: false

  def tool_entry_content(%{tool_response: nil}), do: "Waiting for tool output..."

  def tool_entry_content(%{tool_response: tool_response}) when is_map(tool_response),
    do: tool_response_content(tool_response)

  def tool_entry_content(_tool_entry), do: ""

  def tool_call_arguments_text(tool_call) do
    case Map.get(tool_call, "arguments") || Map.get(tool_call, :arguments) do
      nil -> ""
      arguments -> inspect(arguments, pretty: true, limit: :infinity, width: 80)
    end
  end

  def thinking_default_expanded?(message) do
    streaming_message?(message) and not message_has_content?(message)
  end

  def estimated_cost_label(message) do
    with usage when is_map(usage) <- metadata_value(message, "usage"),
         cost when is_number(cost) <- usage_cost(usage) do
      "Est. cost #{format_currency(cost)}"
    else
      _ -> nil
    end
  end

  def visible_message?(%{role: "tool"}), do: false
  def visible_message?(%{role: "checkpoint"}), do: false

  def visible_message?(message) do
    not assistant_message?(message) or
      delegated_message?(message) or
      streaming_message?(message) or
      message_has_content?(message) or
      assistant_tool_calls(message) != [] or
      tool_responses(message) != []
  end

  defp load_chat_room(socket, id) do
    case Chat.get_chat_room(socket.assigns.current_scope, id) do
      %{} = chat_room ->
        messages = Chat.list_messages(chat_room)
        visible_messages = visible_messages(messages)

        socket
        |> assign(:chat_room, chat_room)
        |> assign(:page_title, chat_room.title || "Chat")
        |> assign(:latest_message_id, latest_message_id(visible_messages))
        |> refresh_sidebar_chat_rooms()
        |> bump_messages_revision()
        |> stream(:messages, visible_messages, reset: true)
        |> sync_main_stream(messages)

      nil ->
        case Chat.get_chat_room_for_user(socket.assigns.current_scope.user, id) do
          %{} = chat_room ->
            redirect(socket, to: switch_path(chat_room.organization_id, ~p"/chat/#{id}"))

          nil ->
            raise Ecto.NoResultsError, query: App.Chat.ChatRoom
        end
    end
  end

  defp refresh_chat_messages(socket) do
    chat_room = Chat.get_chat_room!(socket.assigns.current_scope, socket.assigns.chat_room.id)
    messages = Chat.list_messages(chat_room)
    visible_messages = visible_messages(messages)

    socket
    |> assign(:chat_room, chat_room)
    |> assign(:latest_message_id, latest_message_id(visible_messages))
    |> refresh_sidebar_chat_rooms()
    |> bump_messages_revision()
    |> stream(:messages, visible_messages, reset: true)
    |> sync_main_stream(messages)
  end

  defp refresh_sidebar_chat_rooms(socket) do
    assign(
      socket,
      :sidebar_chat_rooms,
      App.Chat.list_chat_rooms_for_sidebar(socket.assigns.current_scope)
    )
  end

  defp switch_path(organization_id, return_to) do
    ~p"/organizations/switch/#{organization_id}?return_to=#{return_to}"
  end

  defp assign_message_form(socket, params) do
    assign(socket, :message_form, to_form(params, as: :message))
  end

  defp active_agent_for_room(%{chat_room_agents: agents}) do
    case Enum.find(agents, & &1.is_active) || List.first(agents) do
      %{agent: agent} -> agent
      _ -> nil
    end
  end

  defp active_agent_for_room(_), do: nil

  def room_agents(%{chat_room_agents: chat_room_agents}) do
    Enum.map(chat_room_agents, & &1.agent)
  end

  def room_agents(_chat_room), do: []

  def active_agent_label(chat_room) do
    case active_agent_for_room(chat_room) do
      nil -> "Choose an active agent"
      agent -> agent.name
    end
  end

  def active_agent_id(chat_room) do
    case active_agent_for_room(chat_room) do
      nil -> nil
      agent -> agent.id
    end
  end

  def agent_count_label(agents) do
    case length(agents) do
      1 -> "1 agent"
      count -> "#{count} agents"
    end
  end

  defp begin_stream(socket, placeholder_message) do
    streaming_message_id = placeholder_message && placeholder_message.id
    streaming_message_agent = placeholder_message && placeholder_message.agent
    streaming_message_inserted_at = placeholder_message && placeholder_message.inserted_at
    streaming_content = if placeholder_message, do: placeholder_message.content || "", else: ""

    streaming_thinking =
      if placeholder_message, do: message_thinking(placeholder_message) || "", else: ""

    streaming_tool_calls =
      if placeholder_message, do: assistant_tool_calls(placeholder_message), else: []

    streaming_tool_responses =
      if placeholder_message, do: tool_responses(placeholder_message), else: []

    socket
    |> load_chat_room(socket.assigns.chat_room.id)
    |> assign(:streaming_message_id, streaming_message_id)
    |> assign(:streaming_message_agent, streaming_message_agent)
    |> assign(:streaming_message_inserted_at, streaming_message_inserted_at)
    |> assign(:streaming_content, streaming_content)
    |> assign(:streaming_thinking, streaming_thinking)
    |> assign(:streaming_tool_calls, streaming_tool_calls)
    |> assign(:streaming_tool_responses, streaming_tool_responses)
    |> assign(:streaming_token_count, 0)
    |> assign(:streaming_active?, true)
  end

  defp stream_run_opts(socket) do
    active_agent = active_agent_for_room(socket.assigns.chat_room)
    [thinking_mode: agent_thinking_mode(active_agent)]
  end

  defp agent_thinking_mode(%{extra_params: extra_params}) when is_map(extra_params) do
    cond do
      Map.get(extra_params, "thinking") == "enabled" ->
        "enabled"

      Map.get(extra_params, :thinking) == "enabled" ->
        "enabled"

      Map.get(extra_params, "reasoning_effort") in ["minimal", "low", "medium", "high", "xhigh"] ->
        "enabled"

      Map.get(extra_params, :reasoning_effort) in ["minimal", "low", "medium", "high", "xhigh"] ->
        "enabled"

      true ->
        "disabled"
    end
  end

  defp agent_thinking_mode(_agent), do: "disabled"

  defp reset_main_stream(socket) do
    socket
    |> assign(:streaming_message_id, nil)
    |> assign(:streaming_message_agent, nil)
    |> assign(:streaming_message_inserted_at, nil)
    |> assign(:streaming_content, nil)
    |> assign(:streaming_thinking, nil)
    |> assign(:streaming_tool_calls, [])
    |> assign(:streaming_tool_responses, [])
    |> assign(:streaming_token_count, 0)
    |> assign(:streaming_active?, false)
  end

  defp maybe_stream_main_placeholder(%{assigns: %{streaming_message_id: nil}} = socket),
    do: socket

  defp maybe_stream_main_placeholder(socket) do
    stream_insert_message(socket, build_main_stream_message(socket))
  end

  defp build_main_stream_message(socket) do
    %{
      id: socket.assigns.streaming_message_id,
      role: "assistant",
      content: blank_to_nil(socket.assigns.streaming_content),
      status: stream_placeholder_status(socket.assigns.streaming_content),
      metadata: current_stream_metadata(socket),
      agent: socket.assigns.streaming_message_agent,
      inserted_at: socket.assigns.streaming_message_inserted_at || DateTime.utc_now(),
      chat_room_id: socket.assigns.chat_room.id
    }
  end

  defp current_stream_metadata(socket) do
    build_message_metadata(
      %{},
      socket.assigns.streaming_thinking,
      socket.assigns.streaming_tool_calls,
      socket.assigns.streaming_tool_responses
    )
  end

  defp delegated_stream_started?(message, agent_message_streams) do
    case Map.get(agent_message_streams || %{}, message.id) do
      nil ->
        delegated_stream_started_from_message?(message)

      stream_state ->
        delegated_stream_started_from_state?(stream_state)
    end
  end

  defp delegated_stream_started_from_message?(message) do
    message_has_content?(message) or
      message_thinking(message) not in [nil, ""] or
      tool_responses(message) != [] or
      message.status in [:pending, :streaming]
  end

  defp delegated_stream_started_from_state?(stream_state) do
    (stream_state.content || "") != "" or
      (stream_state.thinking || "") != "" or
      (stream_state.tool_responses || []) != []
  end

  defp clear_agent_stream(socket, message_id) do
    update(socket, :agent_message_streams, &Map.delete(&1, message_id))
  end

  defp stream_agent_message_chunk(socket, message_id, token) do
    case current_agent_stream(socket, message_id) do
      nil ->
        socket

      stream_state ->
        new_content = append_text(stream_state.content, token)
        new_count = stream_state.token_count + 1

        stream_state = %{stream_state | content: new_content, token_count: new_count}
        socket = put_agent_stream_state(socket, message_id, stream_state)

        socket =
          stream_insert_message(
            socket,
            build_agent_stream_message(socket, message_id, stream_state)
          )

        socket
    end
  end

  defp stream_agent_message_thinking_chunk(socket, message_id, token) do
    case current_agent_stream(socket, message_id) do
      nil ->
        socket

      stream_state ->
        updated_state = %{stream_state | thinking: append_text(stream_state.thinking, token)}

        socket
        |> put_agent_stream_state(message_id, updated_state)
        |> stream_insert_message(build_agent_stream_message(socket, message_id, updated_state))
    end
  end

  defp put_agent_stream_tool_response(socket, message_id, tool_result) do
    case current_agent_stream(socket, message_id) do
      nil ->
        socket

      stream_state ->
        updated_state = %{
          stream_state
          | tool_responses: merge_tool_response(stream_state.tool_responses, tool_result)
        }

        socket = put_agent_stream_state(socket, message_id, updated_state)

        socket =
          stream_insert_message(
            socket,
            build_agent_stream_message(socket, message_id, updated_state)
          )

        socket
    end
  end

  defp build_agent_stream_message(socket, message_id, stream_state) do
    %{
      id: message_id,
      role: "assistant",
      content: blank_to_nil(stream_state.content),
      status: stream_placeholder_status(stream_state.content),
      metadata:
        build_message_metadata(
          stream_state.metadata,
          stream_state.thinking,
          stream_state.tool_calls,
          stream_state.tool_responses
        ),
      agent: stream_state.agent,
      inserted_at: stream_state.inserted_at || DateTime.utc_now(),
      chat_room_id: socket.assigns.chat_room.id
    }
  end

  defp put_agent_stream_state(socket, message_id, stream_state) do
    update(socket, :agent_message_streams, &Map.put(&1, message_id, stream_state))
  end

  defp current_agent_stream(socket, message_id) do
    case Map.get(socket.assigns.agent_message_streams, message_id) do
      nil ->
        case Chat.get_message_by_id(message_id) do
          %{chat_room_id: chat_room_id} = message
          when chat_room_id == socket.assigns.chat_room.id ->
            %{
              content: message.content || "",
              thinking: message_thinking(message) || "",
              tool_calls: assistant_tool_calls(message),
              tool_responses: tool_responses(message),
              token_count: 0,
              inserted_at: message.inserted_at,
              agent: message.agent,
              metadata: message.metadata || %{}
            }

          _ ->
            nil
        end

      stream_state ->
        stream_state
    end
  end

  defp same_chat_room_message?(socket, %{chat_room_id: chat_room_id}),
    do: socket.assigns.chat_room && socket.assigns.chat_room.id == chat_room_id

  defp same_chat_room_message?(_socket, _message), do: false

  defp metadata_value(message, key) do
    message
    |> Map.get(:metadata, %{})
    |> Map.get(key)
  end

  defp usage_cost(usage) do
    number_value(usage, "total_cost") ||
      case {number_value(usage, "input_cost"), number_value(usage, "output_cost")} do
        {nil, nil} -> nil
        {input_cost, output_cost} -> (input_cost || 0) + (output_cost || 0)
      end
  end

  defp number_value(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_integer(value) -> value * 1.0
      value when is_float(value) -> value
      _ -> nil
    end
  end

  defp number_value(_map, _key), do: nil

  defp format_currency(cost) when cost >= 1.0,
    do: "$" <> :erlang.float_to_binary(cost, decimals: 2)

  defp format_currency(cost) when cost >= 0.01,
    do: "$" <> :erlang.float_to_binary(cost, decimals: 4)

  defp format_currency(cost), do: "$" <> :erlang.float_to_binary(cost, decimals: 6)

  defp build_message_metadata(existing_metadata, thinking, tool_calls, tool_responses) do
    existing_metadata
    |> normalize_metadata_map()
    |> put_metadata_value("thinking", blank_to_nil(thinking))
    |> put_metadata_value("tool_calls", empty_to_nil(tool_calls))
    |> put_metadata_value("tool_responses", empty_to_nil(tool_responses))
  end

  defp put_metadata_value(metadata, key, nil), do: Map.delete(metadata, key)
  defp put_metadata_value(metadata, key, value), do: Map.put(metadata, key, value)

  defp normalize_metadata_map(nil), do: %{}
  defp normalize_metadata_map(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata_map(_metadata), do: %{}

  defp reset_message_metadata(metadata) do
    metadata
    |> normalize_metadata_map()
    |> Map.drop([
      "usage",
      "thinking",
      "tool_call_turns",
      "tool_responses",
      "finish_reason",
      "provider_meta",
      "error",
      "reasoning_effort"
    ])
  end

  defp stream_placeholder_status(content) when content in [nil, ""], do: :pending
  defp stream_placeholder_status(_content), do: :streaming

  defp latest_message_id(messages) do
    case List.last(messages) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp maybe_put_agent_id(attrs, nil), do: attrs
  defp maybe_put_agent_id(attrs, agent_id), do: Map.put(attrs, :agent_id, agent_id)

  defp put_main_stream_tool_response(socket, tool_result) do
    socket
    |> update(:streaming_tool_responses, &merge_tool_response(&1 || [], tool_result))
    |> maybe_stream_main_placeholder()
  end

  defp maybe_switch_subscription(socket, chat_room_id) do
    previous_chat_room_id = socket.assigns.subscribed_chat_room_id

    if previous_chat_room_id && previous_chat_room_id != chat_room_id do
      Chat.unsubscribe_chat_room(previous_chat_room_id)
    end

    if connected?(socket) && previous_chat_room_id != chat_room_id do
      Chat.subscribe_chat_room(chat_room_id)
    end

    assign(socket, :subscribed_chat_room_id, chat_room_id)
  end

  defp sync_main_stream(socket, messages) do
    case Enum.find(
           messages,
           &(assistant_message?(&1) and not delegated_message?(&1) and Chat.stream_running?(&1.id))
         ) do
      nil ->
        reset_main_stream(socket)

      message ->
        sync_main_stream_from_message(socket, message)
    end
  end

  defp sync_main_stream_from_message(socket, %{id: message_id} = message) do
    if Chat.stream_running?(message_id) do
      socket
      |> assign(:streaming_message_id, message.id)
      |> assign(:streaming_message_agent, message.agent)
      |> assign(:streaming_message_inserted_at, message.inserted_at)
      |> assign(:streaming_content, message.content || "")
      |> assign(:streaming_thinking, message_thinking(message) || "")
      |> assign(:streaming_tool_calls, assistant_tool_calls(message))
      |> assign(:streaming_tool_responses, tool_responses(message))
      |> assign(:streaming_active?, true)
    else
      reset_main_stream(socket)
    end
  end

  defp sync_main_stream_from_message(socket, _message), do: socket

  defp merge_tool_response(tool_responses, tool_response) do
    case Map.get(tool_response, "id") do
      nil ->
        tool_responses ++ [tool_response]

      tool_response_id ->
        case Enum.find_index(tool_responses, &(Map.get(&1, "id") == tool_response_id)) do
          nil ->
            tool_responses ++ [tool_response]

          index ->
            List.replace_at(
              tool_responses,
              index,
              Map.merge(Enum.at(tool_responses, index), tool_response)
            )
        end
    end
  end

  defp stream_insert_message(socket, message) do
    socket
    |> bump_messages_revision()
    |> stream_insert(:messages, message, at: -1)
  end

  defp bump_messages_revision(socket) do
    update(socket, :messages_revision, &((&1 || 0) + 1))
  end

  defp visible_messages(messages) do
    Enum.filter(messages, &visible_message?/1)
  end

  defp tool_call_id(tool_call) when is_map(tool_call) do
    Map.get(tool_call, "id") || Map.get(tool_call, :id)
  end

  defp tool_response_id(tool_response) when is_map(tool_response) do
    Map.get(tool_response, "id") || Map.get(tool_response, :id)
  end

  defp tool_response_id(_tool_response), do: nil

  defp hidden_tool_call?(tool_call) do
    tool_call
    |> Map.get("name", Map.get(tool_call, :name))
    |> hidden_tool_name?()
  end

  defp hidden_tool_response?(tool_response) do
    tool_response
    |> Map.get("name", Map.get(tool_response, :name))
    |> hidden_tool_name?()
  end

  defp hidden_tool_name?(name) when is_binary(name), do: name in @hidden_tool_names
  defp hidden_tool_name?(_name), do: false

  defp append_text(current, token), do: (current || "") <> token

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp set_active_agent(socket, agent_id) do
    chat_room = socket.assigns.chat_room

    if Enum.any?(chat_room.chat_room_agents, &(&1.agent_id == agent_id)) do
      case Chat.set_active_agent(chat_room, agent_id) do
        :ok ->
          Chat.broadcast_chat_room_from(chat_room.id, self(), {:active_agent_changed, agent_id})
          load_chat_room(socket, chat_room.id)

        {:error, _reason} ->
          put_flash(socket, :error, "Failed to set active agent")
      end
    else
      socket
    end
  end

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp changeset_error(%Ecto.Changeset{errors: errors}) do
    errors |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end) |> Enum.join(", ")
  end

  defp changeset_error(reason), do: user_error_message(reason)

  defp user_error_message({:error, reason}), do: user_error_message(reason)
  defp user_error_message({reason, _stacktrace}), do: user_error_message(reason)

  defp user_error_message(%{reason: reason}) when not is_nil(reason),
    do: user_error_message(reason)

  defp user_error_message(%{"reason" => reason}) when not is_nil(reason),
    do: user_error_message(reason)

  defp user_error_message(%{response_body: %{"message" => message}}) when is_binary(message),
    do: message

  defp user_error_message(%{"response_body" => %{"message" => message}}) when is_binary(message),
    do: message

  defp user_error_message(%{message: message}) when is_binary(message), do: message
  defp user_error_message(%{"message" => message}) when is_binary(message), do: message
  defp user_error_message(%{__exception__: true} = exception), do: Exception.message(exception)
  defp user_error_message(reason) when is_binary(reason), do: reason

  defp user_error_message(reason) when is_atom(reason),
    do: Phoenix.Naming.humanize(to_string(reason))

  defp user_error_message(_reason), do: "Unexpected error"

  def render_markdown(nil), do: ""

  def render_markdown(content) when is_binary(content) do
    MDEx.new(streaming: true)
    |> MDExGFM.attach()
    |> MDEx.Document.put_markdown(content)
    |> MDEx.to_html!()
  end

  def render_markdown(_), do: ""
end
