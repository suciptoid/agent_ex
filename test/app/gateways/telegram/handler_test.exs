defmodule App.Gateways.Telegram.HandlerTest do
  use App.DataCase, async: false

  alias App.Gateways
  alias App.Gateways.Telegram.Handler

  import App.AgentsFixtures
  import App.ProvidersFixtures

  setup do
    user = App.UsersFixtures.user_fixture()
    organization = App.OrganizationsFixtures.organization_fixture(user)
    scope = App.OrganizationsFixtures.organization_scope_fixture(user, organization: organization)

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

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", payload}
    assert payload["chat_id"] == "1234"
    assert payload["text"] == "Gateway Agent: Need support"
    assert payload["parse_mode"] == "MarkdownV2"

    assert %App.Gateways.Channel{} = Gateways.get_channel(gateway, 1234)
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

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", initial_payload}
    assert initial_payload["text"] == "Gateway Agent: Need support"

    original_channel = Gateways.get_channel(gateway, 1234)
    original_chat_room_id = original_channel.chat_room_id

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

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", fresh_payload}
    assert fresh_payload["text"] == "Gateway Agent: Fresh context"
  end

  test "telegram relay retries with escaped MarkdownV2 when Telegram rejects raw content", %{
    user: user,
    scope: scope
  } do
    provider = provider_fixture(user)
    agent = agent_fixture(user, %{provider: provider, name: "Gateway Agent"})
    attempt_counter = start_supervised!({Agent, fn -> 0 end})
    stub_telegram_markdown_retry_api(self(), attempt_counter)

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
                 "text" => "Need support. (ASAP) #1!"
               }
             })

    assert_receive {:telegram_chat_action, "/bottelegram-token/sendChatAction", _action_payload}

    assert_receive {:telegram_send_message_attempt, 1, first_payload}
    assert first_payload["parse_mode"] == "MarkdownV2"
    assert first_payload["text"] == "Gateway Agent: Need support. (ASAP) #1!"

    assert_receive {:telegram_send_message_attempt, 2, second_payload}
    assert second_payload["parse_mode"] == "MarkdownV2"

    assert second_payload["text"] ==
             "Gateway Agent: Need support\\. \\(ASAP\\) \\#1\\!"
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

  defp stub_telegram_markdown_retry_api(test_pid, attempt_counter) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      case conn.request_path do
        "/bottelegram-token/sendChatAction" ->
          send(test_pid, {:telegram_chat_action, conn.request_path, payload})
          Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))

        "/bottelegram-token/sendMessage" ->
          attempt =
            Agent.get_and_update(attempt_counter, fn current_attempt ->
              next_attempt = current_attempt + 1
              {next_attempt, next_attempt}
            end)

          send(test_pid, {:telegram_send_message_attempt, attempt, payload})

          if attempt == 1 do
            Plug.Conn.send_resp(
              conn,
              400,
              ~s({"ok":false,"error_code":400,"description":"Bad Request: can't parse entities: Character '.' is reserved and must be escaped with the preceding '\\\\'"})
            )
          else
            Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
          end

        _other ->
          send(test_pid, {:telegram_request, conn.request_path, payload})
          Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
      end
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
