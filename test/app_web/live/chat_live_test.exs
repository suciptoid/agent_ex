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
          commander_agent_id: agent.id
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
          "commander_agent_id" => agent.id
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
          commander_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Plan next week"}
      })
      |> render_submit()

      reloaded_room = Chat.get_chat_room!(scope, room.id)
      [user_message, assistant_message] = Chat.list_messages(reloaded_room)

      assert user_message.content == "Plan next week"
      assert assistant_message.content == "Lead Agent: Plan next week"
      assert has_element?(live_view, "#message-#{user_message.id}")
      assert has_element?(live_view, "#message-#{assistant_message.id}")
    end
  end
end
