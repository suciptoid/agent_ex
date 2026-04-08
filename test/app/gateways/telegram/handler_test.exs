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

    assert {:ok, _stream_pid} =
             Handler.handle_update(gateway, %{
               "message" => %{
                 "chat" => %{"id" => 1234},
                 "from" => %{"id" => 5678, "first_name" => "Alex"},
                 "text" => "Need support"
               }
             })

    assert_receive {:preloaded_provider_runner_called, streamed_agent, messages}
    assert streamed_agent.id == agent.id
    assert Ecto.assoc_loaded?(streamed_agent.provider)
    assert streamed_agent.provider.id == provider.id
    assert Enum.any?(messages, &(&1.role == "user" and &1.content == "Need support"))

    assert_receive {:telegram_send_message, "/bottelegram-token/sendMessage", payload}
    assert payload["chat_id"] == "1234"
    assert payload["text"] == "Gateway Agent: Need support"

    assert %App.Gateways.Channel{} = Gateways.get_channel(gateway, 1234)
  end

  defp stub_telegram_api(test_pid) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:telegram_send_message, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
    end)
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:app, key)
  defp restore_app_env(key, value), do: Application.put_env(:app, key, value)
end
