defmodule AppWeb.ChatLiveTest do
  use AppWeb.ConnCase, async: false

  alias App.Chat

  import App.AgentsFixtures
  import App.ChatFixtures
  import App.ProvidersFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  setup do
    previous_runner = Application.get_env(:app, :agent_runner)
    Application.put_env(:app, :agent_runner, App.TestSupport.AgentRunnerStub)

    on_exit(fn ->
      if previous_runner do
        Application.put_env(:app, :agent_runner, previous_runner)
      else
        Application.delete_env(:app, :agent_runner)
      end
    end)

    :ok
  end

  describe "chat rooms" do
    test "lists chat rooms for the current user", %{conn: conn, user: user} do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Room Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Strategy Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat")

      assert has_element?(live_view, "#chat-room-#{room.id}")
    end

    test "creates a chat room", %{conn: conn, user: user, scope: scope} do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Commander"})

      {:ok, live_view, _html} = live(conn, ~p"/chat")

      live_view
      |> element("#new-chat-button")
      |> render_click()

      assert_patch(live_view, ~p"/chat/new")

      live_view
      |> form("#chat-room-form", %{
        "chat_room" => %{
          "title" => "Planning Room",
          "agent_ids" => ["", agent.id],
          "active_agent_id" => agent.id
        }
      })
      |> render_submit()

      created_room = Enum.find(Chat.list_chat_rooms(scope), &(&1.title == "Planning Room"))
      assert_redirect(live_view, ~p"/chat/#{created_room.id}")
    end
  end

  describe "chat room show" do
    test "sends a message and streams the assistant reply", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Delivery Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Plan next week"}
      })
      |> render_submit()

      # The streaming response is handled asynchronously via Task.async.
      # Use :sys.get_state to flush the LV mailbox and wait for the task to complete.
      # We wait until the assistant message has "completed" status (after streaming finishes).
      [user_message, assistant_message] =
        Enum.reduce_while(1..30, [], fn _, _ ->
          _ = :sys.get_state(live_view.pid)
          reloaded_room = Chat.get_chat_room!(scope, room.id)
          messages = Chat.list_messages(reloaded_room)

          completed_assistant =
            Enum.find(messages, &(&1.role == "assistant" && &1.status == "completed"))

          if completed_assistant, do: {:halt, messages}, else: {:cont, []}
        end)

      assert user_message.content == "Plan next week"
      assert assistant_message.content == "Lead Agent: Plan next week"
      assert has_element?(live_view, "#message-#{user_message.id}")
      assert has_element?(live_view, "#message-#{assistant_message.id}")
    end

    test "renders delegated agent streaming updates", %{conn: conn, user: user} do
      provider = provider_fixture(user)
      lead_agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})
      delegated_agent = agent_fixture(user, %{provider: provider, name: "Research Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Delegation Room",
          agents: [lead_agent, delegated_agent],
          active_agent_id: lead_agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      assert {:ok, placeholder_message} =
               Chat.create_message(room, %{
                 role: "assistant",
                 content: nil,
                 status: "requesting",
                 agent_id: delegated_agent.id,
                 metadata: %{"delegated" => true, "tool_name" => "ask_agent"}
               })

      send(live_view.pid, {:agent_message_created, placeholder_message})
      _ = :sys.get_state(live_view.pid)

      assert has_element?(live_view, "#message-#{placeholder_message.id}")

      send(live_view.pid, {:agent_message_stream_chunk, placeholder_message.id, "Hello"})
      send(live_view.pid, {:agent_message_stream_chunk, placeholder_message.id, " world"})
      _ = :sys.get_state(live_view.pid)

      assert has_element?(live_view, "#message-#{placeholder_message.id}", "Hello world")

      assert {:ok, completed_message} =
               Chat.update_message(placeholder_message, %{
                 content: "Hello world",
                 status: "completed"
               })

      send(live_view.pid, {:agent_message_updated, completed_message})
      _ = :sys.get_state(live_view.pid)

      assert has_element?(live_view, "#message-#{completed_message.id}", "Hello world")
    end
  end
end
