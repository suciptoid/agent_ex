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
    test "renders blank chat room with centered agent selection controls", %{
      conn: conn,
      user: user
    } do
      provider = provider_fixture(user)
      _agent = agent_fixture(user, %{provider: provider, name: "Room Agent"})

      {:ok, live_view, _html} = live(conn, ~p"/chat")

      assert has_element?(live_view, "#chat-message-form")
      assert has_element?(live_view, "#chat-message-input")
      assert has_element?(live_view, "#new-chat-agent-selector")
      assert has_element?(live_view, "#new-chat-agent-selector-add-agent-trigger")
    end

    test "creates a chat room on first message, navigates to it, and auto-generates a title", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      provider = provider_fixture(user)
      _agent = agent_fixture(user, %{provider: provider, name: "Commander"})

      {:ok, live_view, _html} = live(conn, ~p"/chat")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Hello agent"}
      })
      |> render_submit()

      created_room = List.first(Chat.list_chat_rooms(scope))
      assert created_room

      path = ~p"/chat/#{created_room.id}"
      assert_redirect(live_view, path)

      {:ok, show_view, _html} = live(conn, path)

      titled_room =
        wait_for_chat_room(show_view, scope, created_room.id, fn room ->
          if room.title not in [nil, ""], do: room
        end)

      assert titled_room.title == "Hello agent"

      assert_eventually(show_view, fn ->
        has_element?(show_view, "#chat-room-title", "Hello agent")
      end)
    end
  end

  describe "chat room show" do
    test "hides the header agent selector until the room has messages", %{
      conn: conn,
      user: user
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Solo Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Empty Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      refute has_element?(live_view, "#chat-agent-selector")
    end

    test "renders a sidebar loading spinner for rooms with pending assistant replies", %{
      conn: conn,
      user: user
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Spinner Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Spinner Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      assert {:ok, _pending_message} =
               Chat.create_message(room, %{
                 role: "assistant",
                 content: nil,
                 status: :pending,
                 agent_id: agent.id,
                 metadata: %{}
               })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      assert has_element?(live_view, "#sidebar-chat-loading-#{room.id}")
    end

    test "shows reasoning controls for supported models and forwards the selected effort", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      previous_stub_config = Application.get_env(:app, App.TestSupport.AgentRunnerStub)
      Application.put_env(:app, App.TestSupport.AgentRunnerStub, notify_pid: self())

      on_exit(fn ->
        if previous_stub_config do
          Application.put_env(:app, App.TestSupport.AgentRunnerStub, previous_stub_config)
        else
          Application.delete_env(:app, App.TestSupport.AgentRunnerStub)
        end
      end)

      provider =
        provider_fixture(user, %{
          name: "My Anthropic",
          provider: "anthropic",
          api_key: "sk-ant-test"
        })

      agent =
        agent_fixture(user, %{
          provider: provider,
          name: "Reasoner",
          model: "anthropic:claude-haiku-4-5"
        })

      room =
        chat_room_fixture(user, %{
          title: "Reasoning Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      assert has_element?(live_view, "#chat-reasoning-effort-menu")

      render_click(live_view, "set-reasoning-effort", %{"value" => "none"})

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Keep it concise"}
      })
      |> render_submit()

      assert_receive {:agent_runner_streaming_opts, opts}
      assert opts[:reasoning_effort] == :none

      assistant_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :completed))
        end)

      assert assistant_message.content == "Reasoner: Keep it concise"
    end

    test "hides reasoning controls for models without reasoning support", %{
      conn: conn,
      user: user
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, model: "openai:gpt-4.1-mini"})

      room =
        chat_room_fixture(user, %{
          title: "Fast Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      refute has_element?(live_view, "#chat-reasoning-effort-menu")
    end

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

      [user_message, assistant_message] =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          completed_assistant =
            Enum.find(messages, &(&1.role == "assistant" && &1.status == :completed))

          if completed_assistant, do: messages, else: nil
        end)

      assert user_message.content == "Plan next week"
      assert assistant_message.content == "Lead Agent: Plan next week"
      assert has_element?(live_view, "#message-#{user_message.id}")
      assert has_element?(live_view, "#message-#{assistant_message.id}")
      assert has_element?(live_view, "#chat-agent-selector")
      assert has_element?(live_view, "#chat-message-submit[aria-label='Send message']")
    end

    test "regenerates the latest assistant message in place", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Retry Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Retry this"}
      })
      |> render_submit()

      assistant_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :completed))
        end)

      previous_updated_at = assistant_message.updated_at
      assert has_element?(live_view, "#regenerate-message-#{assistant_message.id}")

      live_view
      |> element("#regenerate-message-#{assistant_message.id}")
      |> render_click()

      regenerated_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.id == assistant_message.id and message.status == :completed and
              DateTime.compare(message.updated_at, previous_updated_at) == :gt
          end)
        end)

      reloaded_room = Chat.get_chat_room!(scope, room.id)
      messages = Chat.list_messages(reloaded_room)

      assert regenerated_message.id == assistant_message.id
      assert length(messages) == 2
      assert has_element?(live_view, "#message-#{assistant_message.id}")
    end

    test "renders thinking, tool responses, and cost metadata", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      Application.put_env(:app, :agent_runner, App.TestSupport.StreamingMetadataRunnerStub)

      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Research Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Metadata Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Fetch the data"}
      })
      |> render_submit()

      assistant_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :completed))
        end)

      assert assistant_message.metadata["thinking"] == "Planning the lookup"
      assert length(assistant_message.metadata["tool_responses"]) == 1

      assert has_element?(
               live_view,
               "#message-thinking-#{assistant_message.id} details summary",
               "Thinking"
             )

      assert has_element?(live_view, "#message-tool-response-#{assistant_message.id}-0")

      assert has_element?(
               live_view,
               "#message-tool-response-#{assistant_message.id}-0 details summary",
               "web_fetch"
             )

      assert has_element?(
               live_view,
               "#message-thinking-#{assistant_message.id} details:not([open])"
             )

      refute has_element?(
               live_view,
               "#message-tool-response-#{assistant_message.id}-0",
               "https://example.com/data.txt"
             )

      assert has_element?(live_view, "#message-cost-#{assistant_message.id}")
    end

    test "broadcasts assistant streaming updates to another open tab before completion", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_stub_config = Application.get_env(:app, App.TestSupport.SlowStreamingRunnerStub)

      tool_response = %{
        "id" => "tool_sync",
        "name" => "web_fetch",
        "arguments" => %{"url" => "https://example.com/live.json"},
        "content" => "live payload",
        "status" => "ok"
      }

      Application.put_env(:app, :agent_runner, App.TestSupport.SlowStreamingRunnerStub)

      Application.put_env(:app, App.TestSupport.SlowStreamingRunnerStub,
        notify_pid: self(),
        thinking: "Working on it",
        tool_response: tool_response
      )

      on_exit(fn ->
        if previous_runner do
          Application.put_env(:app, :agent_runner, previous_runner)
        else
          Application.delete_env(:app, :agent_runner)
        end

        if previous_stub_config do
          Application.put_env(:app, App.TestSupport.SlowStreamingRunnerStub, previous_stub_config)
        else
          Application.delete_env(:app, App.TestSupport.SlowStreamingRunnerStub)
        end
      end)

      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Sync Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Shared Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, first_tab, _html} = live(conn, ~p"/chat/#{room.id}")
      {:ok, second_tab, _html} = live(conn, ~p"/chat/#{room.id}")

      first_tab
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Sync this now"}
      })
      |> render_submit()

      assert_receive {:slow_runner_started, runner_pid}

      user_message =
        wait_for_messages(first_tab, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "user" && &1.content == "Sync this now"))
        end)

      assistant_message =
        wait_for_messages(first_tab, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :pending))
        end)

      assert_eventually(second_tab, fn ->
        has_element?(second_tab, "#message-#{user_message.id}", "Sync this now")
      end)

      assert_eventually(second_tab, fn ->
        has_element?(second_tab, "#message-#{assistant_message.id}")
      end)

      assert_eventually(second_tab, fn ->
        has_element?(second_tab, "#message-#{assistant_message.id}", "S")
      end)

      assert_eventually(second_tab, fn ->
        has_element?(
          second_tab,
          "#message-tool-response-#{assistant_message.id}-0 details summary",
          "web_fetch"
        )
      end)

      assert_eventually(second_tab, fn ->
        has_element?(
          second_tab,
          "#message-tool-response-#{assistant_message.id}-0",
          "live payload"
        )
      end)

      refute Chat.get_chat_room!(scope, room.id)
             |> Chat.list_messages()
             |> Enum.any?(&(&1.role == "assistant" && &1.status == :completed))

      ref = Process.monitor(runner_pid)
      send(runner_pid, :continue)
      assert_receive {:DOWN, ^ref, :process, ^runner_pid, _reason}

      completed_message =
        wait_for_messages(nil, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :completed))
        end)

      assert completed_message.content == "Sync Agent: Sync this now"

      assert_eventually(first_tab, fn ->
        not Chat.stream_running?(assistant_message.id)
      end)
    end

    test "cancels an in-flight streamed response", %{conn: conn, user: user, scope: scope} do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_stub_config = Application.get_env(:app, App.TestSupport.SlowStreamingRunnerStub)

      Application.put_env(:app, :agent_runner, App.TestSupport.SlowStreamingRunnerStub)

      Application.put_env(:app, App.TestSupport.SlowStreamingRunnerStub, notify_pid: self())

      on_exit(fn ->
        if previous_runner do
          Application.put_env(:app, :agent_runner, previous_runner)
        else
          Application.delete_env(:app, :agent_runner)
        end

        if previous_stub_config do
          Application.put_env(:app, App.TestSupport.SlowStreamingRunnerStub, previous_stub_config)
        else
          Application.delete_env(:app, App.TestSupport.SlowStreamingRunnerStub)
        end
      end)

      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Slow Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Slow Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Stop this reply"}
      })
      |> render_submit()

      assert_receive {:slow_runner_started, runner_pid}

      assistant_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :pending))
        end)

      assert has_element?(live_view, "#message-#{assistant_message.id}")
      assert has_element?(live_view, "#chat-message-submit[aria-label='Stop generating']")

      ref = Process.monitor(runner_pid)

      live_view
      |> element("#chat-message-submit")
      |> render_click()

      assert_receive {:DOWN, ^ref, :process, ^runner_pid, _reason}

      cancelled_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.id == assistant_message.id && &1.status == :error))
        end)

      assert cancelled_message.content =~ "S"
      assert cancelled_message.metadata["cancelled"] == true
      assert has_element?(live_view, "#chat-message-submit[aria-label='Send message']")
    end

    test "continues streaming after leaving the chat room", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_stub_config = Application.get_env(:app, App.TestSupport.SlowStreamingRunnerStub)

      Application.put_env(:app, :agent_runner, App.TestSupport.SlowStreamingRunnerStub)
      Application.put_env(:app, App.TestSupport.SlowStreamingRunnerStub, notify_pid: self())

      on_exit(fn ->
        if previous_runner do
          Application.put_env(:app, :agent_runner, previous_runner)
        else
          Application.delete_env(:app, :agent_runner)
        end

        if previous_stub_config do
          Application.put_env(:app, App.TestSupport.SlowStreamingRunnerStub, previous_stub_config)
        else
          Application.delete_env(:app, App.TestSupport.SlowStreamingRunnerStub)
        end
      end)

      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Slow Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Background Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Finish even if I leave"}
      })
      |> render_submit()

      assert_receive {:slow_runner_started, runner_pid}

      assistant_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :pending))
        end)

      assert has_element?(live_view, "#message-#{assistant_message.id}")

      assert {:error, {:live_redirect, %{to: to}}} =
               live_view
               |> element("main a.inline-flex[href='/chat']")
               |> render_click()

      assert to == "/chat"

      send(runner_pid, :continue)

      completed_message =
        wait_for_messages(nil, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.id == assistant_message.id && &1.status == :completed))
        end)

      assert completed_message.content == "Slow Agent: Finish even if I leave"
      assert completed_message.agent_id == agent.id
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
                 status: :pending,
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
                 status: :completed
               })

      send(live_view.pid, {:agent_message_updated, completed_message})
      _ = :sys.get_state(live_view.pid)

      assert has_element?(live_view, "#message-#{completed_message.id}", "Hello world")
    end
  end

  defp wait_for_messages(live_view, scope, room_id, callback) do
    Enum.reduce_while(1..30, nil, fn _, _acc ->
      if live_view, do: _ = :sys.get_state(live_view.pid)
      reloaded_room = Chat.get_chat_room!(scope, room_id)
      messages = Chat.list_messages(reloaded_room)

      case callback.(messages) do
        nil -> {:cont, nil}
        result -> {:halt, result}
      end
    end) || flunk("expected chat messages to reach the desired state")
  end

  defp wait_for_chat_room(live_view, scope, room_id, callback) do
    Enum.reduce_while(1..30, nil, fn _, _acc ->
      if live_view, do: _ = :sys.get_state(live_view.pid)

      case callback.(Chat.get_chat_room!(scope, room_id)) do
        nil -> {:cont, nil}
        result -> {:halt, result}
      end
    end) || flunk("expected chat room to reach the desired state")
  end

  defp assert_eventually(live_view, callback) do
    Enum.reduce_while(1..30, nil, fn _, _acc ->
      _ = :sys.get_state(live_view.pid)

      if callback.() do
        {:halt, :ok}
      else
        {:cont, nil}
      end
    end) || flunk("expected live view to reach the desired state")
  end
end
