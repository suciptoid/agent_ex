defmodule AppWeb.ChatLiveTest do
  use AppWeb.ConnCase, async: false

  alias App.Chat
  alias App.Gateways
  alias App.Organizations

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
      assert has_element?(live_view, "#chat-composer-shell")
      assert has_element?(live_view, "#chat-message-input")
      assert has_element?(live_view, "#chat-message-input.field-sizing-content")
      assert has_element?(live_view, "#chat-message-controls")
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

      submit_result =
        live_view
        |> form("#chat-message-form", %{
          "message" => %{"content" => "Hello agent"}
        })
        |> render_submit()

      created_room = List.first(Chat.list_chat_rooms(scope))
      assert created_room

      path = ~p"/chat/#{created_room.id}"
      assert assert_redirect(live_view, path) == %{}

      {:ok, show_view, _html} = follow_redirect(submit_result, conn, path)

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
    test "renders chat shell with a closed agent sidebar", %{
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

      assert has_element?(live_view, "#chat-room-shell[data-agent-sidebar-open='false']")
      assert has_element?(live_view, "#chat-agent-sidebar")
      assert has_element?(live_view, "#chat-agent-sidebar-toggle")
      assert has_element?(live_view, "#chat-agent-selector")
      refute has_element?(live_view, "a", "Back")
      assert has_element?(live_view, "#chat-messages")
      assert has_element?(live_view, "#chat-messages-empty-state.max-w-4xl")
      assert has_element?(live_view, "#chat-composer-shell")
      assert has_element?(live_view, "#chat-message-input.field-sizing-content")
      refute has_element?(live_view, "#chat-message-input[data-max-height-vh]")
      assert has_element?(live_view, "#chat-message-controls")
      assert has_element?(live_view, "#sidebar-user-menu p.truncate", user.email)
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

    test "renders sidebar controls for gateway-linked rooms", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Gateway Agent"})

      # Pre-seed user mapping so channel is auto-approved
      Organizations.put_secret_value(scope, "channel_user_map:telegram:5678", user.id)

      {:ok, gateway} =
        Gateways.create_gateway(scope, %{
          "name" => "Support Bot",
          "type" => "telegram",
          "token" => "telegram-token",
          "config" => %{"agent_id" => agent.id, "allow_all_users" => true}
        })

      {:ok, channel} =
        Gateways.find_or_create_channel(gateway, %{
          external_chat_id: "1234",
          external_user_id: "5678",
          external_username: "Alex"
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{channel.chat_room_id}")

      assert has_element?(live_view, "#sidebar-chat-gateway-icon-#{channel.chat_room_id}")
      assert has_element?(live_view, "#sidebar-delete-chat-#{channel.chat_room_id}")
    end

    test "deletes the current chat room from the sidebar and navigates to /chat", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Delete Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Delete Me",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      assert {:error, {:live_redirect, %{to: to}}} =
               live_view
               |> element("#sidebar-delete-chat-#{room.id}")
               |> render_click()

      assert to == "/chat"
      refute Chat.get_chat_room(scope, room.id)
    end

    test "does not render checkpoint messages in the visible transcript", %{
      conn: conn,
      user: user
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Checkpoint Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Checkpoint Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      user_message = message_fixture(room, %{role: "user", content: "Visible message"})

      checkpoint_message =
        message_fixture(room, %{
          role: "checkpoint",
          content: "Checkpoint summary should stay hidden",
          agent_id: agent.id,
          metadata: %{"up_to_position" => user_message.position}
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      assert has_element?(live_view, "#message-#{user_message.id}")
      refute has_element?(live_view, "#message-#{checkpoint_message.id}")
    end

    test "uses the active agent thinking mode for supported models", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      configure_agent_runner_stub(self())

      provider =
        provider_fixture(user, %{
          name: "My Gemini",
          provider: "google",
          api_key: "google-test-key"
        })

      agent =
        agent_fixture(user, %{
          provider: provider,
          name: "Reasoner",
          model: "gemini-2.5-flash",
          thinking_mode: "disabled"
        })

      room =
        chat_room_fixture(user, %{
          title: "Reasoning Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      refute has_element?(live_view, "#chat-reasoning-effort-menu")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Keep it concise"}
      })
      |> render_submit()

      assert_receive {:agent_runner_streaming_opts, opts}
      assert opts[:thinking_mode] == "disabled"

      assistant_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :completed))
        end)

      assert assistant_message.content == "Reasoner: Keep it concise"
    end

    test "defaults agent thinking mode to disabled", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      configure_agent_runner_stub(self())

      provider =
        provider_fixture(user, %{
          name: "My Gemini",
          provider: "google",
          api_key: "google-test-key"
        })

      agent =
        agent_fixture(user, %{
          provider: provider,
          name: "Reasoner",
          model: "gemini-2.5-flash"
        })

      room =
        chat_room_fixture(user, %{
          title: "Gemini Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      refute has_element?(live_view, "#chat-reasoning-effort-menu")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Use the default thinking mode"}
      })
      |> render_submit()

      assert_receive {:agent_runner_streaming_opts, opts}
      assert opts[:thinking_mode] == "disabled"

      assistant_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :completed))
        end)

      assert assistant_message.content == "Reasoner: Use the default thinking mode"
    end

    test "forwards enabled thinking mode for agents that opt in", %{
      conn: conn,
      user: user
    } do
      configure_agent_runner_stub(self())

      provider = provider_fixture(user)

      agent =
        agent_fixture(user, %{
          provider: provider,
          model: "gpt-4.1-mini",
          thinking_mode: "enabled"
        })

      room =
        chat_room_fixture(user, %{
          title: "Fast Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      refute has_element?(live_view, "#chat-reasoning-effort-menu")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Think through it"}
      })
      |> render_submit()

      assert_receive {:agent_runner_streaming_opts, opts}
      assert opts[:thinking_mode] == "enabled"
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
      assert has_element?(live_view, "#chat-agent-sidebar")
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

    test "regenerate uses the current active agent", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      provider = provider_fixture(user)
      lead_agent = agent_fixture(user, %{provider: provider, name: "Lead Agent"})
      backup_agent = agent_fixture(user, %{provider: provider, name: "Backup Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Switch Retry Room",
          agents: [lead_agent, backup_agent],
          active_agent_id: lead_agent.id
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

      live_view
      |> element("#chat-agent-selector-set-#{backup_agent.id}")
      |> render_click()

      live_view
      |> element("#regenerate-message-#{assistant_message.id}")
      |> render_click()

      regenerated_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.id == assistant_message.id and message.status == :completed and
              message.agent_id == backup_agent.id and
              message.content == "Backup Agent: Retry this"
          end)
        end)

      assert regenerated_message.agent_id == backup_agent.id

      assert has_element?(
               live_view,
               "#message-#{assistant_message.id}",
               "Backup Agent: Retry this"
             )
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

      {tool_call_message, tool_message, final_assistant_message} =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          tool_call_message =
            Enum.find(messages, fn message ->
              message.role == "assistant" and length(message.metadata["tool_calls"] || []) == 1
            end)

          tool_message = Enum.find(messages, &(&1.role == "tool" && &1.status == :completed))

          final_assistant_message =
            Enum.find(messages, fn message ->
              message.role == "assistant" and message.status == :completed and
                message.content == "Research Agent: Fetch the data"
            end)

          if tool_call_message && tool_message && final_assistant_message do
            {tool_call_message, tool_message, final_assistant_message}
          end
        end)

      assert tool_call_message.metadata["thinking"] == "Planning the lookup"
      assert length(tool_call_message.metadata["tool_calls"]) == 1
      assert is_nil(tool_message.metadata["thinking"])
      assert final_assistant_message.metadata["thinking"] == "Summarizing the fetched payload"

      assert has_element?(
               live_view,
               "#message-thinking-#{tool_call_message.id} details summary",
               "Thinking"
             )

      assert has_element?(live_view, "#message-tool-#{tool_call_message.id}-0")

      assert has_element?(
               live_view,
               "#message-tool-#{tool_call_message.id}-0 details summary",
               "web_fetch"
             )

      assert has_element?(
               live_view,
               "#message-thinking-#{tool_call_message.id} details:not([open])"
             )

      refute has_element?(live_view, "#message-#{tool_message.id}")

      assert has_element?(
               live_view,
               "#message-thinking-#{final_assistant_message.id} details summary",
               "Thinking"
             )

      assert has_element?(live_view, "#message-cost-#{final_assistant_message.id}")
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

      tool_message =
        wait_for_messages(nil, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "tool" && &1.status == :completed))
        end)

      tool_call_message =
        wait_for_messages(nil, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and length(message.metadata["tool_calls"] || []) == 1
          end)
        end)

      assert_eventually(second_tab, fn ->
        has_element?(
          second_tab,
          "#message-tool-#{tool_call_message.id}-0 details summary",
          "web_fetch"
        )
      end)

      refute has_element?(second_tab, "#message-#{tool_message.id}")

      refute Chat.get_chat_room!(scope, room.id)
             |> Chat.list_messages()
             |> Enum.any?(fn message ->
               message.role == "assistant" and message.status == :completed and
                 is_binary(message.content) and message.content != ""
             end)

      ref = Process.monitor(runner_pid)
      send(runner_pid, :continue)
      assert_receive {:DOWN, ^ref, :process, ^runner_pid, _reason}

      completed_message =
        wait_for_messages(nil, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and message.status == :completed and
              message.content == "Sync Agent: Sync this now"
          end)
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

      [{worker_pid, _value}] = Registry.lookup(App.Chat.StreamRegistry, assistant_message.id)
      worker_ref = Process.monitor(worker_pid)

      assert has_element?(live_view, "#message-#{assistant_message.id}")

      assert {:error, {:live_redirect, %{to: to}}} =
               live_view
               |> element("#sidebar-new-chat-link")
               |> render_click()

      assert to == "/chat"

      send(runner_pid, :continue)

      completed_message =
        wait_for_messages(nil, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.id == assistant_message.id && &1.status == :completed))
        end)

      assert_receive {:DOWN, ^worker_ref, :process, ^worker_pid, _reason}
      assert completed_message.content == "Slow Agent: Finish even if I leave"
      assert completed_message.agent_id == agent.id
    end

    test "hides internal title tools and merges tool results into the assistant block", %{
      conn: conn,
      user: user
    } do
      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Mini"})

      room =
        chat_room_fixture(user, %{
          title: "Grouped Tools",
          agents: [agent],
          active_agent_id: agent.id
        })

      _user_message = message_fixture(room, %{role: "user", content: "run df -h on shell"})

      internal_tool_call_message =
        message_fixture(room, %{
          role: "assistant",
          agent_id: agent.id,
          content: nil,
          status: :completed,
          metadata: %{
            "tool_calls" => [
              %{
                "id" => "title_1",
                "name" => "update_chatroom_title",
                "arguments" => %{"title" => "Run df -h"}
              }
            ]
          }
        })

      internal_tool_message =
        message_fixture(room, %{
          role: "tool",
          name: "update_chatroom_title",
          tool_call_id: "title_1",
          parent_message_id: internal_tool_call_message.id,
          content: "Title set to: Run df -h",
          metadata: %{"arguments" => %{"title" => "Run df -h"}}
        })

      visible_tool_call_message =
        message_fixture(room, %{
          role: "assistant",
          agent_id: agent.id,
          content: nil,
          status: :completed,
          metadata: %{
            "tool_calls" => [
              %{
                "id" => "shell_1",
                "name" => "shell",
                "arguments" => %{"command" => "df -h"}
              }
            ]
          }
        })

      visible_tool_message =
        message_fixture(room, %{
          role: "tool",
          name: "shell",
          tool_call_id: "shell_1",
          parent_message_id: visible_tool_call_message.id,
          content: "Filesystem output",
          metadata: %{"arguments" => %{"command" => "df -h"}}
        })

      final_message =
        message_fixture(room, %{
          role: "assistant",
          agent_id: agent.id,
          content: "Here's the output of df -h from the shell you requested."
        })

      subagent_tool_call_message =
        message_fixture(room, %{
          role: "assistant",
          agent_id: agent.id,
          content: "I checked the other agents before delegating.",
          status: :completed,
          metadata: %{
            "tool_calls" => [
              %{
                "id" => "subagent_list_1",
                "name" => "subagent_lists",
                "arguments" => %{}
              }
            ],
            "tool_responses" => [
              %{
                "id" => "subagent_list_1",
                "name" => "subagent_lists",
                "content" => Jason.encode!(%{"agents" => [%{"name" => "Research Agent"}]}),
                "status" => "ok"
              }
            ]
          }
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      refute has_element?(live_view, "#message-#{internal_tool_call_message.id}")
      refute has_element?(live_view, "#message-#{internal_tool_message.id}")
      refute render(live_view) =~ "update_chatroom_title"

      assert has_element?(live_view, "#message-tool-#{visible_tool_call_message.id}-0")

      assert has_element?(
               live_view,
               "#message-tool-#{visible_tool_call_message.id}-0 details summary",
               "shell"
             )

      assert has_element?(live_view, "#message-tool-#{subagent_tool_call_message.id}-0")

      assert has_element?(
               live_view,
               "#message-tool-#{subagent_tool_call_message.id}-0 details summary",
               "subagent_lists"
             )

      refute has_element?(live_view, "#message-#{visible_tool_message.id}")
      assert has_element?(live_view, "#message-#{final_message.id}")
    end

    test "renders subagent placeholder updates without hiding the pending placeholder", %{
      conn: conn,
      user: user
    } do
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
                 metadata: %{
                   "delegated" => true,
                   "subagent" => true,
                   "tool_name" => "subagent_spawn"
                 }
               })

      send(live_view.pid, {:agent_message_created, placeholder_message})
      _ = :sys.get_state(live_view.pid)

      assert has_element?(live_view, "#message-#{placeholder_message.id}")
      assert has_element?(live_view, "#message-streaming-#{placeholder_message.id}")

      send(live_view.pid, {:agent_message_stream_chunk, placeholder_message.id, "Hello"})
      send(live_view.pid, {:agent_message_stream_chunk, placeholder_message.id, " world"})
      _ = :sys.get_state(live_view.pid)

      assert has_element?(live_view, "#message-#{placeholder_message.id}", "Hello world")
      assert has_element?(live_view, "#message-streaming-#{placeholder_message.id}")

      assert {:ok, completed_message} =
               Chat.update_message(placeholder_message, %{
                 content: "Hello world",
                 status: :completed
               })

      send(live_view.pid, {:agent_message_updated, completed_message})
      _ = :sys.get_state(live_view.pid)

      assert has_element?(live_view, "#message-#{completed_message.id}", "Hello world")
    end

    test "creates the follow-up pending assistant message only after tool results arrive", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_stub_config = Application.get_env(:app, App.TestSupport.ToolTurnPauseRunnerStub)

      Application.put_env(:app, :agent_runner, App.TestSupport.ToolTurnPauseRunnerStub)

      Application.put_env(:app, App.TestSupport.ToolTurnPauseRunnerStub,
        notify_pid: self(),
        thinking: "Planning the lookup",
        tool_response: %{
          "id" => "tool_1",
          "name" => "web_fetch",
          "arguments" => %{"url" => "https://example.com"},
          "content" => "sample payload",
          "status" => "ok"
        }
      )

      on_exit(fn ->
        if previous_runner do
          Application.put_env(:app, :agent_runner, previous_runner)
        else
          Application.delete_env(:app, :agent_runner)
        end

        if previous_stub_config do
          Application.put_env(:app, App.TestSupport.ToolTurnPauseRunnerStub, previous_stub_config)
        else
          Application.delete_env(:app, App.TestSupport.ToolTurnPauseRunnerStub)
        end
      end)

      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Tool Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Tool Waiting Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Fetch it"}
      })
      |> render_submit()

      assert_receive {:tool_turn_runner_started, runner_pid}

      tool_call_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and length(message.metadata["tool_calls"] || []) == 1
          end)
        end)

      assert has_element?(live_view, "#message-#{tool_call_message.id}")

      assert has_element?(
               live_view,
               "#message-tool-#{tool_call_message.id}-0",
               "Waiting for tool output"
             )

      refute Enum.any?(Chat.list_messages(Chat.get_chat_room!(scope, room.id)), fn message ->
               message.role == "assistant" and message.status == :pending and
                 message.id != tool_call_message.id
             end)

      send(runner_pid, :emit_tool_result)
      assert_receive {:tool_turn_runner_tool_result_emitted, ^runner_pid}

      assert_eventually(live_view, fn ->
        has_element?(live_view, "#message-tool-#{tool_call_message.id}-0", "sample payload") and
          not has_element?(
            live_view,
            "#message-tool-#{tool_call_message.id}-0",
            "Waiting for tool output"
          )
      end)

      followup_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and message.status == :pending and
              message.id != tool_call_message.id
          end)
        end)

      assert followup_message.id != tool_call_message.id
      assert has_element?(live_view, "#message-#{followup_message.id}")
      assert has_element?(live_view, "#message-streaming-#{followup_message.id}")

      ref = Process.monitor(runner_pid)
      send(runner_pid, :continue)
      assert_receive {:DOWN, ^ref, :process, ^runner_pid, _reason}

      completed_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and message.status == :completed and
              message.content == "Tool Agent: Fetch it"
          end)
        end)

      assert completed_message.id == followup_message.id
    end

    test "does not carry prior tool rows into the next streamed assistant message", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      previous_runner = Application.get_env(:app, :agent_runner)
      previous_stub_config = Application.get_env(:app, App.TestSupport.ToolTurnPauseRunnerStub)

      Application.put_env(:app, :agent_runner, App.TestSupport.ToolTurnPauseRunnerStub)

      Application.put_env(:app, App.TestSupport.ToolTurnPauseRunnerStub,
        notify_pid: self(),
        tool_response: %{
          "id" => "tool_repeat",
          "name" => "web_fetch",
          "arguments" => %{"url" => "https://example.com"},
          "content" => "sample payload",
          "status" => "ok"
        }
      )

      on_exit(fn ->
        if previous_runner do
          Application.put_env(:app, :agent_runner, previous_runner)
        else
          Application.delete_env(:app, :agent_runner)
        end

        if previous_stub_config do
          Application.put_env(:app, App.TestSupport.ToolTurnPauseRunnerStub, previous_stub_config)
        else
          Application.delete_env(:app, App.TestSupport.ToolTurnPauseRunnerStub)
        end
      end)

      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Tool Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Carryover Guard",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Fetch the first item"}
      })
      |> render_submit()

      assert_receive {:tool_turn_runner_started, first_runner_pid}

      first_tool_call_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and length(message.metadata["tool_calls"] || []) == 1
          end)
        end)

      send(first_runner_pid, :emit_tool_result)
      assert_receive {:tool_turn_runner_tool_result_emitted, ^first_runner_pid}

      first_followup_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and message.status == :pending and
              message.id != first_tool_call_message.id
          end)
        end)

      refute has_element?(live_view, "#message-tool-#{first_followup_message.id}-0")

      first_runner_ref = Process.monitor(first_runner_pid)
      send(first_runner_pid, :continue)
      assert_receive {:DOWN, ^first_runner_ref, :process, ^first_runner_pid, _reason}

      wait_for_messages(live_view, scope, room.id, fn messages ->
        Enum.find(messages, fn message ->
          message.role == "assistant" and message.status == :completed and
            message.id == first_followup_message.id
        end)
      end)

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Fetch the second item"}
      })
      |> render_submit()

      assert_receive {:tool_turn_runner_started, second_runner_pid}

      second_tool_call_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and
              length(message.metadata["tool_calls"] || []) == 1 and
              message.id != first_tool_call_message.id
          end)
        end)

      assert has_element?(
               live_view,
               "#message-tool-#{second_tool_call_message.id}-0",
               "Waiting for tool output"
             )

      send(second_runner_pid, :emit_tool_result)
      assert_receive {:tool_turn_runner_tool_result_emitted, ^second_runner_pid}

      second_followup_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, fn message ->
            message.role == "assistant" and message.status == :pending and
              message.id not in [
                first_tool_call_message.id,
                first_followup_message.id,
                second_tool_call_message.id
              ]
          end)
        end)

      assert has_element?(live_view, "#message-#{second_followup_message.id}")
      refute has_element?(live_view, "#message-tool-#{second_followup_message.id}-0")
      refute has_element?(live_view, "#message-#{second_followup_message.id}", "sample payload")

      second_runner_ref = Process.monitor(second_runner_pid)
      send(second_runner_pid, :continue)
      assert_receive {:DOWN, ^second_runner_ref, :process, ^second_runner_pid, _reason}

      wait_for_messages(live_view, scope, room.id, fn messages ->
        Enum.find(messages, fn message ->
          message.role == "assistant" and message.status == :completed and
            message.id == second_followup_message.id
        end)
      end)
    end

    test "ignores orphan tool responses on synthetic streamed assistant rows" do
      message = %{
        role: "assistant",
        status: :pending,
        metadata: %{
          "tool_responses" => [
            %{
              "id" => "tool_orphan",
              "name" => "web_fetch",
              "content" => "stale payload",
              "status" => "ok"
            }
          ]
        }
      }

      assert AppWeb.ChatLive.Show.assistant_tool_entries(message) == []
    end

    test "renders only the exception message for failed assistant runs", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      Application.put_env(:app, :agent_runner, App.TestSupport.FailingAgentRunnerStub)

      provider = provider_fixture(user)
      agent = agent_fixture(user, %{provider: provider, name: "Explosive Agent"})

      room =
        chat_room_fixture(user, %{
          title: "Failure Room",
          agents: [agent],
          active_agent_id: agent.id
        })

      {:ok, live_view, _html} = live(conn, ~p"/chat/#{room.id}")

      live_view
      |> form("#chat-message-form", %{
        "message" => %{"content" => "Fail now"}
      })
      |> render_submit()

      failed_message =
        wait_for_messages(live_view, scope, room.id, fn messages ->
          Enum.find(messages, &(&1.role == "assistant" && &1.status == :error))
        end)

      assert failed_message.content ==
               "Invalid value: 'default'. Supported values are: 'none', 'minimal', 'low', 'medium', 'high', and 'xhigh'."

      refute failed_message.content =~ "API request failed"
      refute failed_message.content =~ "response_body"
    end
  end

  defp wait_for_messages(live_view, scope, room_id, callback) do
    Enum.reduce_while(1..100, nil, fn _, _acc ->
      if live_view, do: _ = :sys.get_state(live_view.pid)
      reloaded_room = Chat.get_chat_room!(scope, room_id)
      messages = Chat.list_messages(reloaded_room)

      case callback.(messages) do
        nil -> {:cont, nil}
        result -> {:halt, result}
      end
    end) || flunk("expected chat messages to reach the desired state")
  end

  defp configure_agent_runner_stub(notify_pid) do
    previous_stub_config = Application.get_env(:app, App.TestSupport.AgentRunnerStub)
    Application.put_env(:app, App.TestSupport.AgentRunnerStub, notify_pid: notify_pid)

    on_exit(fn ->
      if previous_stub_config do
        Application.put_env(:app, App.TestSupport.AgentRunnerStub, previous_stub_config)
      else
        Application.delete_env(:app, App.TestSupport.AgentRunnerStub)
      end
    end)
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
