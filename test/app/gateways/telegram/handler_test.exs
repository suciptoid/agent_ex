defmodule App.Gateways.Telegram.HandlerTest do
  use App.DataCase, async: false

  alias App.Chat
  alias App.Gateways
  alias App.Gateways.Telegram.Handler
  alias App.Tasks

  import App.AgentsFixtures
  import App.ProvidersFixtures

  setup do
    user = App.UsersFixtures.user_fixture()
    organization = App.OrganizationsFixtures.organization_fixture(user)
    scope = App.OrganizationsFixtures.organization_scope_fixture(user, organization: organization)

    # Pre-seed user mapping so Telegram channels are auto-approved in tests
    App.Organizations.put_secret_value(scope, "channel_user_map:telegram:5678", user.id)

    previous_runner = Application.get_env(:app, :agent_runner)

    previous_runner_config =
      Application.get_env(:app, App.TestSupport.PreloadedProviderRunnerStub)

    previous_client_config = Application.get_env(:app, App.Gateways.Telegram.Client)

    Application.put_env(:app, :agent_runner, App.TestSupport.PreloadedProviderRunnerStub)
    Application.put_env(:app, App.TestSupport.PreloadedProviderRunnerStub, notify_pid: self())

    Application.put_env(:app, App.Gateways.Telegram.Client,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn ->
      restore_app_env(:agent_runner, previous_runner)
      restore_app_env(App.TestSupport.PreloadedProviderRunnerStub, previous_runner_config)
      restore_app_env(App.Gateways.Telegram.Client, previous_client_config)
    end)

    %{user: user, scope: scope}
  end

  test "gateway chat preloads the agent provider and relays the assistant reply", %{
    user: user,
    scope: scope
  } do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Gateway Agent"})
    stub_telegram_api(self())

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Support Bot",
        "type" => "telegram",
        "token" => "telegram-token",
        "config" => %{
          "agent_id" => agent.id,
          "allow_all_users" => true
        }
      })

    flush_mailbox()

    assert {:ok, _stream_pid} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 1234},
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "Need support"
               }
             })

    assert_receive {:telegram_chat_action, "/bottelegram-token/sendChatAction", action_payload}
    assert action_payload["chat_id"] == "1234"
    assert action_payload["action"] == "typing"

    assert_receive {:preloaded_provider_runner_called, streamed_agent, messages}
    assert streamed_agent.id == agent.id
    assert Ecto.assoc_loaded?(streamed_agent.provider)
    assert streamed_agent.provider.id == provider.id
    assert Enum.any?(messages, &(&1.role == "user" and &1.content == "Need support"))
    assert_receive {:preloaded_provider_runner_opts, opts}
    assert Keyword.get(opts, :user_id) == user.id

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", payload}, 1_000
    assert payload["chat_id"] == "1234"
    assert payload["text"] == "Gateway Agent: Need support"
    assert payload["parse_mode"] == "MarkdownV2"

    assert %App.Gateways.Channel{} = channel = Gateways.get_channel(gateway, 1234)

    persisted_user_message =
      scope
      |> Chat.get_chat_room!(channel.chat_room_id)
      |> Chat.list_messages()
      |> Enum.find(&(&1.role == "user"))

    assert persisted_user_message.user_id == user.id
  end

  test "telegram /new rotates the channel onto a fresh chat room", %{user: user, scope: scope} do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Gateway Agent"})
    stub_telegram_api(self())

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Support Bot",
        "type" => "telegram",
        "token" => "telegram-token",
        "config" => %{
          "agent_id" => agent.id,
          "allow_all_users" => true
        }
      })

    assert {:ok, _stream_pid} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 1234},
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "Need support"
               }
             })

    assert_receive {:preloaded_provider_runner_called, initial_agent, initial_messages}
    assert initial_agent.id == agent.id
    assert Enum.map(initial_messages, &{&1.role, &1.content}) == [{"user", "Need support"}]

    assert_receive {:telegram_chat_action, "/bottelegram-token/sendChatAction",
                    _initial_action_payload}

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", initial_payload}
    assert initial_payload["text"] == "Gateway Agent: Need support"

    original_channel = Gateways.get_channel(gateway, 1234)
    original_chat_room_id = original_channel.chat_room_id

    {:ok, scheduled_task} =
      Tasks.create_task(scope, %{
        "name" => "Notify Ops",
        "prompt" => "Send daily status",
        "run_mode" => "once",
        "next_run_input" => "2026-04-24T09:00",
        "agent_ids" => [agent.id],
        "main_agent_id" => agent.id,
        "notification_chat_room_id" => original_chat_room_id
      })

    assert {:ok, _response} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 1234},
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "/new"
               }
             })

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", reset_payload}

    assert reset_payload["text"] ==
             "Started a fresh chat. Send your next message when you're ready."

    rotated_channel = Gateways.get_channel(gateway, 1234)
    assert rotated_channel.chat_room_id != original_chat_room_id

    refreshed_task = Tasks.get_task!(scope, scheduled_task.id)
    assert refreshed_task.notification_chat_room_id == rotated_channel.chat_room_id

    original_chat_room = Chat.get_chat_room!(scope, original_chat_room_id)
    rotated_chat_room = Chat.get_chat_room!(scope, rotated_channel.chat_room_id)

    assert original_chat_room.type == :archived
    assert rotated_chat_room.type == :gateway
    assert rotated_chat_room.parent_id == original_chat_room.id

    assert {:ok, _stream_pid} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 1234},
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "Fresh context"
               }
             })

    assert_receive {:preloaded_provider_runner_called, streamed_agent, messages}
    assert streamed_agent.id == agent.id
    assert Enum.map(messages, &{&1.role, &1.content}) == [{"user", "Fresh context"}]

    assert_receive {:telegram_chat_action, "/bottelegram-token/sendChatAction",
                    _fresh_action_payload}

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", fresh_payload}
    assert fresh_payload["text"] == "Gateway Agent: Fresh context"
  end

  test "gateway-created chat rooms include all assigned agents and activate the configured default",
       %{
         user: user,
         scope: scope
       } do
    primary_provider = provider_fixture(user)
    fallback_provider = provider_fixture(user)
    primary_agent = agent_fixture(user, %{provider: primary_provider, name: "Primary Agent"})
    fallback_agent = agent_fixture(user, %{provider: fallback_provider, name: "Fallback Agent"})

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Multi Agent Bot",
        "type" => "telegram",
        "token" => "telegram-token",
        "config" => %{
          "agent_ids" => [primary_agent.id, fallback_agent.id],
          "agent_id" => fallback_agent.id,
          "allow_all_users" => true
        }
      })

    {:ok, channel} =
      Gateways.find_or_create_channel(gateway, %{
        external_chat_id: "4321",
        external_user_id: "5678",
        external_username: "Gateway User"
      })

    chat_room = Chat.get_chat_room!(scope, channel.chat_room_id)
    active_chat_room_agent = Enum.find(chat_room.chat_room_agents, & &1.is_active)

    assert Enum.sort(Enum.map(chat_room.chat_room_agents, & &1.agent_id)) ==
             Enum.sort([primary_agent.id, fallback_agent.id])

    assert active_chat_room_agent.agent_id == fallback_agent.id
  end

  test "approving a pending channel backfills prior channel user messages with the mapped user id",
       %{
         scope: scope
       } do
    provider = provider_fixture(scope.user)
    agent = agent_fixture(scope.user, %{provider: provider, name: "Gateway Agent"})
    stub_telegram_api(self())

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Pending Bot",
        "type" => "telegram",
        "token" => "pending-token",
        "config" => %{
          "agent_id" => agent.id,
          "allow_all_users" => true
        }
      })

    flush_mailbox()

    assert {:ok, _response} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 2222},
                 "from" => %{"id" => 9999, "first_name" => "Pending"},
                 "text" => "Please approve me"
               }
             })

    channel = Gateways.get_channel(gateway, 2222)

    [pending_message] =
      channel.chat_room_id
      |> then(&Chat.get_chat_room!(scope, &1))
      |> Chat.list_messages()
      |> Enum.filter(&(&1.role == "user"))

    assert pending_message.user_id == nil

    {:ok, _approved_channel} = Gateways.approve_channel(scope, channel, scope.user.id)

    [approved_message] =
      channel.chat_room_id
      |> then(&Chat.get_chat_room!(scope, &1))
      |> Chat.list_messages()
      |> Enum.filter(&(&1.role == "user"))

    assert approved_message.user_id == scope.user.id
  end

  test "telegram relay preserves bold markdown while escaping surrounding punctuation", %{
    user: user,
    scope: scope
  } do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Gateway Agent"})
    stub_telegram_api(self())

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Support Bot",
        "type" => "telegram",
        "token" => "telegram-token",
        "config" => %{
          "agent_id" => agent.id,
          "allow_all_users" => true
        }
      })

    flush_mailbox()

    assert {:ok, _stream_pid} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 1234},
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "Bitcoin (BTC) terhadap USD hari ini: **$70 993** per BTC. 🚀"
               }
             })

    assert_receive {:telegram_chat_action, "/bottelegram-token/sendChatAction", _action_payload}

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", payload}
    assert payload["parse_mode"] == "MarkdownV2"

    assert payload["text"] ==
             "Gateway Agent: Bitcoin \\(BTC\\) terhadap USD hari ini: *$70 993* per BTC\\. 🚀"
  end

  test "telegram group messages use the group title for the channel and preserve sender names", %{
    user: user,
    scope: scope
  } do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Gateway Agent"})
    stub_telegram_api(self())

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Support Bot",
        "type" => "telegram",
        "token" => "telegram-token",
        "config" => %{
          "agent_id" => agent.id,
          "allow_all_users" => true
        }
      })

    group_chat_id = -100_204_050_607

    assert {:ok, _stream_pid} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{
                   "id" => group_chat_id,
                   "type" => "supergroup",
                   "title" => "Ops War Room"
                 },
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "Need support"
               }
             })

    assert_receive {:preloaded_provider_runner_called, streamed_agent, first_messages}
    assert streamed_agent.id == agent.id

    assert Enum.map(Enum.filter(first_messages, &(&1.role == "user")), &{&1.name, &1.content}) ==
             [{"Alex", "Need support"}]

    assert_receive {:telegram_chat_action, "/bottelegram-token/sendChatAction", typing_payload}
    assert typing_payload["chat_id"] == to_string(group_chat_id)
    assert typing_payload["action"] == "typing"

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", first_payload},
                   1_000

    assert first_payload["chat_id"] == to_string(group_chat_id)

    channel = Gateways.get_channel(gateway, group_chat_id)
    assert channel.external_username == "Ops War Room"
    assert channel.metadata["chat_type"] == "supergroup"
    assert channel.metadata["chat_title"] == "Ops War Room"

    chat_room = Chat.get_chat_room!(scope, channel.chat_room_id)
    assert chat_room.title == "Ops War Room"

    assert {:ok, _stream_pid} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{
                   "id" => group_chat_id,
                   "type" => "supergroup",
                   "title" => "Ops War Room"
                 },
                 "from" => %{"id" => 9012, "first_name" => "Jamie"},
                 "text" => "Fresh input"
               }
             })

    assert_receive {:preloaded_provider_runner_called, next_agent, next_messages}
    assert next_agent.id == agent.id

    assert Enum.map(Enum.filter(next_messages, &(&1.role == "user")), &{&1.name, &1.content}) ==
             [{"Alex", "Need support"}, {"Jamie", "Fresh input"}]

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", second_payload}
    assert second_payload["chat_id"] == to_string(group_chat_id)
  end

  test "gateway messages are broadcast to open chat subscribers", %{user: user, scope: scope} do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Gateway Agent"})
    stub_telegram_api(self())

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Support Bot",
        "type" => "telegram",
        "token" => "telegram-token",
        "config" => %{
          "agent_id" => agent.id,
          "allow_all_users" => true
        }
      })

    assert {:ok, _response} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 1234},
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "/start"
               }
             })

    channel = Gateways.get_channel(gateway, 1234)
    Chat.subscribe_chat_room(channel.chat_room_id)
    flush_mailbox()

    assert {:ok, _stream_pid} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 1234},
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "Need support"
               }
             })

    assert_receive {:user_message_created, user_message}
    assert user_message.chat_room_id == channel.chat_room_id
    assert user_message.role == "user"
    assert user_message.content == "Need support"

    assert_receive {:agent_message_created, assistant_message}
    assert assistant_message.chat_room_id == channel.chat_room_id
    assert assistant_message.role == "assistant"
    assert assistant_message.status == :pending
  end

  defp stub_telegram_api(test_pid) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      case conn.request_path do
        "/bottelegram-token/sendChatAction" ->
          send(test_pid, {:telegram_chat_action, conn.request_path, payload})

        "/bottelegram-token/sendMessage" ->
          send(test_pid, {:telegram_send_message, conn.request_path, payload})

        _other ->
          send(test_pid, {:telegram_request, conn.request_path, payload})
      end

      Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
    end)
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:app, key)
  defp restore_app_env(key, value), do: Application.put_env(:app, key, value)

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
