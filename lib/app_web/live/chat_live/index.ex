defmodule AppWeb.ChatLive.Index do
  use AppWeb, :live_view

  alias App.Agents
  alias App.Chat

  @impl true
  def mount(_params, _session, socket) do
    available_agents = Agents.list_agents(socket.assigns.current_scope)
    default_agent = List.first(available_agents)

    {:ok,
     socket
     |> assign(:page_title, "New Chat")
     |> assign(:available_agents, available_agents)
     |> assign(:selected_agents, if(default_agent, do: [default_agent], else: []))
     |> assign(:active_agent_id, default_agent && default_agent.id)
     |> assign_message_form(%{"content" => ""})}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"message" => message_params}, socket) do
    {:noreply, assign_message_form(socket, message_params)}
  end

  def handle_event("send", %{"message" => %{"content" => content}}, socket) do
    content = String.trim(content || "")

    if content == "" do
      {:noreply, put_flash(socket, :error, "Message cannot be blank")}
    else
      selected_agents = socket.assigns.selected_agents
      active_agent_id = socket.assigns.active_agent_id

      if selected_agents == [] do
        {:noreply, put_flash(socket, :error, "Select at least one agent to start chatting")}
      else
        agent_ids = Enum.map(selected_agents, & &1.id)

        case Chat.create_chat_room(socket.assigns.current_scope, %{
               "agent_ids" => agent_ids,
               "active_agent_id" => active_agent_id
             }) do
          {:ok, chat_room} ->
            case Chat.create_message(chat_room, %{role: "user", content: content}) do
              {:ok, user_message} ->
                Chat.broadcast_chat_room(
                  chat_room.id,
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
                    case Chat.start_stream(chat_room, messages, placeholder_message) do
                      {:ok, _pid} ->
                        Chat.broadcast_chat_room(
                          chat_room.id,
                          {:agent_message_created, placeholder_message}
                        )

                        {:noreply,
                         socket
                         |> put_flash(:info, nil)
                         |> push_navigate(to: ~p"/chat/#{chat_room.id}")}

                      {:error, reason} ->
                        {:noreply,
                         put_flash(
                           socket,
                           :error,
                           "Failed to start stream: #{inspect(reason)}"
                         )}
                    end

                  {:error, _reason} ->
                    {:noreply,
                     socket
                     |> push_navigate(to: ~p"/chat/#{chat_room.id}")
                     |> put_flash(:error, "Failed to prepare assistant response")}
                end

              {:error, _changeset} ->
                {:noreply,
                 socket
                 |> push_navigate(to: ~p"/chat/#{chat_room.id}")
                 |> put_flash(:error, "Failed to send message")}
            end

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to create chat room")}
        end
      end
    end
  end

  def handle_event("add-agent", %{"id" => agent_id}, socket) do
    agent = Enum.find(socket.assigns.available_agents, &(&1.id == agent_id))

    if agent && agent not in socket.assigns.selected_agents do
      selected = socket.assigns.selected_agents ++ [agent]
      active_id = socket.assigns.active_agent_id || agent.id

      {:noreply, assign(socket, selected_agents: selected, active_agent_id: active_id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-agent", %{"id" => agent_id}, socket) do
    selected = Enum.reject(socket.assigns.selected_agents, &(&1.id == agent_id))

    active_id =
      if socket.assigns.active_agent_id == agent_id do
        case List.first(selected) do
          nil -> nil
          agent -> agent.id
        end
      else
        socket.assigns.active_agent_id
      end

    {:noreply, assign(socket, selected_agents: selected, active_agent_id: active_id)}
  end

  def handle_event("set-active-agent", %{"id" => agent_id}, socket) do
    {:noreply, set_active_agent(socket, agent_id)}
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

  def active_agent_label(selected_agents, active_agent_id) do
    case Enum.find(selected_agents, &(&1.id == active_agent_id)) || List.first(selected_agents) do
      nil -> "Choose a default agent"
      agent -> agent.name
    end
  end

  def agent_count_label(selected_agents) do
    case length(selected_agents) do
      1 -> "1 agent"
      count -> "#{count} agents"
    end
  end

  defp set_active_agent(socket, agent_id) do
    normalized_agent_id =
      case agent_id do
        "" -> nil
        value -> value
      end

    if is_nil(normalized_agent_id) or
         Enum.any?(socket.assigns.selected_agents, &(&1.id == normalized_agent_id)) do
      assign(socket, :active_agent_id, normalized_agent_id)
    else
      socket
    end
  end
end
