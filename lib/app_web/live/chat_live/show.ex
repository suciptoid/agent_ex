defmodule AppWeb.ChatLive.Show do
  use AppWeb, :live_view

  alias App.Chat

  @stream_db_write_every 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Chat")
     |> assign(:chat_room, nil)
     |> assign(:agent_message_streams, %{})
     |> assign(:latest_message_id, nil)
     |> assign(:streaming_message_id, nil)
     |> assign(:streaming_message_agent, nil)
     |> assign(:streaming_message_inserted_at, nil)
     |> assign(:streaming_content, nil)
     |> assign(:streaming_thinking, nil)
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
        {:ok, _user_message} ->
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
              case Chat.start_stream(chat_room, messages, placeholder_message) do
                {:ok, _pid} ->
                  {:noreply,
                   socket
                   |> begin_stream(placeholder_message)
                   |> assign_message_form(%{"content" => ""})}

                {:error, reason} ->
                  {:noreply,
                   socket
                   |> put_flash(:error, "Failed to start stream: #{inspect(reason)}")
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
        agent_id = message.agent_id || (active_agent && active_agent.id)

        attrs =
          %{
            content: nil,
            status: :pending,
            metadata: reset_message_metadata(message.metadata)
          }
          |> maybe_put_agent_id(agent_id)

        case Chat.update_message(message, attrs) do
          {:ok, placeholder_message} ->
            case Chat.start_stream(chat_room, prior_messages, placeholder_message) do
              {:ok, _pid} ->
                {:noreply, socket |> begin_stream(placeholder_message)}

              {:error, reason} ->
                {:noreply, put_flash(socket, :error, "Failed to regenerate: #{inspect(reason)}")}
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
        {:noreply, put_flash(socket, :error, "Failed to stop stream: #{inspect(reason)}")}
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

  def handle_info({:stream_chunk, _message_id, _token}, socket), do: {:noreply, socket}

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

  def handle_info({:stream_thinking_chunk, _message_id, _token}, socket), do: {:noreply, socket}

  def handle_info(
        {:stream_tool_started, message_id, tool_result},
        %{assigns: %{streaming_message_id: message_id}} = socket
      ) do
    {:noreply, put_main_stream_tool_response(socket, tool_result)}
  end

  def handle_info({:stream_tool_started, _message_id, _tool_result}, socket),
    do: {:noreply, socket}

  def handle_info(
        {:stream_tool_result, message_id, tool_result},
        %{assigns: %{streaming_message_id: message_id}} = socket
      ) do
    {:noreply, put_main_stream_tool_response(socket, tool_result)}
  end

  def handle_info({:stream_tool_result, _message_id, _tool_result}, socket),
    do: {:noreply, socket}

  def handle_info({:agent_message_created, message}, socket) do
    if same_chat_room_message?(socket, message) do
      {:noreply,
       socket
       |> maybe_track_agent_stream(message)
       |> assign(:latest_message_id, message.id)
       |> stream_insert_message(message)}
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
      {:noreply,
       socket
       |> clear_agent_stream(message.id)
       |> assign(:latest_message_id, message.id)
       |> stream_insert_message(message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:active_agent_changed, _agent_id}, socket) do
    {:noreply, load_chat_room(socket, socket.assigns.chat_room.id)}
  end

  def handle_info({:stream_updated, message}, socket) do
    if same_chat_room_message?(socket, message) do
      socket =
        socket
        |> stream_insert_message(message)
        |> sync_main_stream_from_message(message)
        |> maybe_track_agent_stream(message)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
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

  def speaker_name(%{role: "user"}), do: "You"
  def speaker_name(%{agent: %{name: name}}), do: name
  def speaker_name(_message), do: "Assistant"

  def message_icon(%{role: "user"}), do: "hero-user"
  def message_icon(%{role: "assistant"}), do: "hero-cpu-chip"
  def message_icon(%{role: "system"}), do: "hero-command-line"
  def message_icon(%{role: "tool"}), do: "hero-wrench-screwdriver"
  def message_icon(_message), do: "hero-wrench-screwdriver"

  def message_thinking(message), do: metadata_value(message, "thinking")

  def tool_responses(message) do
    message
    |> metadata_value("tool_responses")
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  def tool_response_label(tool_response) do
    name = Map.get(tool_response, "name") || "tool"
    arguments = tool_response |> Map.get("arguments", %{}) |> format_tool_arguments()

    if arguments == "" do
      name
    else
      "#{name}(#{arguments})"
    end
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

  defp load_chat_room(socket, id) do
    chat_room = Chat.get_chat_room!(socket.assigns.current_scope, id)
    messages = Chat.list_messages(chat_room)

    socket
    |> assign(:chat_room, chat_room)
    |> assign(:page_title, chat_room.title)
    |> assign(:latest_message_id, latest_message_id(messages))
    |> stream(:messages, Enum.reverse(messages), reset: true)
    |> sync_main_stream(messages)
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

  defp begin_stream(socket, placeholder_message) do
    streaming_message_id = placeholder_message && placeholder_message.id
    streaming_message_agent = placeholder_message && placeholder_message.agent
    streaming_message_inserted_at = placeholder_message && placeholder_message.inserted_at
    streaming_content = if placeholder_message, do: placeholder_message.content || "", else: ""

    streaming_thinking =
      if placeholder_message, do: message_thinking(placeholder_message) || "", else: ""

    streaming_tool_responses =
      if placeholder_message, do: tool_responses(placeholder_message), else: []

    socket
    |> load_chat_room(socket.assigns.chat_room.id)
    |> assign(:streaming_message_id, streaming_message_id)
    |> assign(:streaming_message_agent, streaming_message_agent)
    |> assign(:streaming_message_inserted_at, streaming_message_inserted_at)
    |> assign(:streaming_content, streaming_content)
    |> assign(:streaming_thinking, streaming_thinking)
    |> assign(:streaming_tool_responses, streaming_tool_responses)
    |> assign(:streaming_token_count, 0)
    |> assign(:streaming_active?, true)
  end

  defp reset_main_stream(socket) do
    socket
    |> assign(:streaming_message_id, nil)
    |> assign(:streaming_message_agent, nil)
    |> assign(:streaming_message_inserted_at, nil)
    |> assign(:streaming_content, nil)
    |> assign(:streaming_thinking, nil)
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
      socket.assigns.streaming_tool_responses
    )
  end

  defp maybe_track_agent_stream(socket, %{id: id, status: status} = message)
       when status in [:pending, :streaming] do
    update(socket, :agent_message_streams, fn streams ->
      Map.put(streams, id, %{
        content: message.content || "",
        thinking: message_thinking(message) || "",
        tool_responses: tool_responses(message),
        token_count: 0,
        inserted_at: message.inserted_at,
        agent: message.agent,
        metadata: message.metadata || %{}
      })
    end)
  end

  defp maybe_track_agent_stream(socket, _message), do: socket

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

        if rem(new_count, @stream_db_write_every) == 0 do
          maybe_update_streaming_message(
            message_id,
            new_content,
            stream_placeholder_status(new_content),
            build_message_metadata(
              stream_state.metadata,
              stream_state.thinking,
              stream_state.tool_responses
            )
          )
        end

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

        maybe_update_streaming_message(
          message_id,
          updated_state.content,
          stream_placeholder_status(updated_state.content),
          build_message_metadata(
            updated_state.metadata,
            updated_state.thinking,
            updated_state.tool_responses
          )
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

  defp format_tool_arguments(nil), do: ""
  defp format_tool_arguments(arguments) when arguments == %{}, do: ""

  defp format_tool_arguments(arguments) do
    arguments
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{tool_value_preview(value)}" end)
    |> truncate_text(80)
  end

  defp tool_value_preview(value) when is_binary(value), do: truncate_text(value, 36)
  defp tool_value_preview(value) when is_number(value), do: to_string(value)
  defp tool_value_preview(value) when is_boolean(value), do: to_string(value)
  defp tool_value_preview(value), do: value |> Jason.encode!() |> truncate_text(36)

  defp truncate_text(text, max_length) when byte_size(text) <= max_length, do: text
  defp truncate_text(text, max_length), do: String.slice(text, 0, max_length) <> "…"

  defp build_message_metadata(existing_metadata, thinking, tool_responses) do
    existing_metadata
    |> normalize_metadata_map()
    |> put_metadata_value("thinking", blank_to_nil(thinking))
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
      "tool_responses",
      "finish_reason",
      "provider_meta",
      "error"
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
    |> update(:streaming_tool_responses, &merge_tool_response(&1, tool_result))
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
      |> assign(:streaming_tool_responses, tool_responses(message))
      |> assign(:streaming_active?, true)
    else
      reset_main_stream(socket)
    end
  end

  defp sync_main_stream_from_message(socket, _message), do: socket

  defp maybe_update_streaming_message(message_id, content, status, metadata) do
    case Chat.get_message_by_id(message_id) do
      nil ->
        :ok

      message ->
        Chat.update_message(message, %{
          content: blank_to_nil(content),
          status: status,
          metadata: metadata
        })
    end
  end

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
    stream_insert(socket, :messages, message, at: 0)
  end

  defp append_text(current, token), do: (current || "") <> token

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp changeset_error(%Ecto.Changeset{errors: errors}) do
    errors |> Enum.map(fn {k, {msg, _}} -> "#{k}: #{msg}" end) |> Enum.join(", ")
  end

  defp changeset_error(reason), do: inspect(reason)

  def render_markdown(nil), do: ""

  def render_markdown(content) when is_binary(content) do
    MDEx.new(streaming: true)
    |> MDExGFM.attach()
    |> MDEx.Document.put_markdown(content)
    |> MDEx.to_html!()
  end

  def render_markdown(_), do: ""
end
