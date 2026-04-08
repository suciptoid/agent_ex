defmodule AppWeb.GatewayLiveTest do
  use AppWeb.ConnCase, async: false

  alias App.Gateways
  alias App.Gateways.Telegram.Webhook, as: TelegramWebhook

  import App.AgentsFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  setup do
    previous_config = Application.get_env(:app, App.Gateways.Telegram.Client)

    Application.put_env(:app, App.Gateways.Telegram.Client,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn ->
      if previous_config do
        Application.put_env(:app, App.Gateways.Telegram.Client, previous_config)
      else
        Application.delete_env(:app, App.Gateways.Telegram.Client)
      end
    end)

    :ok
  end

  test "new gateway form saves active telegram gateways and registers a webhook", %{
    conn: conn,
    user: user,
    scope: scope
  } do
    agent = agent_fixture(user, %{name: "Telegram Support"})
    stub_telegram_webhook(self())

    {:ok, live_view, _html} = live(conn, ~p"/gateways/new")

    assert has_element?(live_view, "#gateway-form")

    assert has_element?(
             live_view,
             "#gateway-form [role=\"option\"][data-value=\"telegram\"]",
             "Telegram Bot"
           )

    assert has_element?(
             live_view,
             "#gateway-form [role=\"option\"][data-value=\"whatsapp_api\"]",
             "WhatsApp API"
           )

    assert has_element?(
             live_view,
             "#gateway-form [role=\"option\"][data-value=\"#{agent.id}\"]",
             "Telegram Support"
           )

    assert has_element?(
             live_view,
             "#gateway-form input[type=\"hidden\"][name=\"gateway[config][allow_all_users]\"][value=\"false\"]"
           )

    assert has_element?(
             live_view,
             "#gateway-form input[type=\"checkbox\"][name=\"gateway[config][allow_all_users]\"][value=\"true\"]"
           )

    live_view
    |> element("#gateway-form")
    |> render_submit(%{
      "gateway" => %{
        "name" => "Support Bot",
        "type" => "telegram",
        "token" => "123456:telegram-bot-token",
        "status" => "active",
        "config" => %{
          "agent_id" => agent.id,
          "allow_all_users" => "false",
          "welcome_message" => "Hello from Telegram"
        }
      }
    })

    assert_patch(live_view, ~p"/gateways")

    [gateway] = Gateways.list_gateways(scope)

    assert gateway.name == "Support Bot"
    assert gateway.type == :telegram
    assert gateway.status == :active
    assert gateway.config.agent_id == agent.id
    assert gateway.config.allow_all_users == false
    assert gateway.config.welcome_message == "Hello from Telegram"

    assert_received {:telegram_set_webhook, "/bot123456:telegram-bot-token/setWebhook", payload}
    assert payload["url"] == TelegramWebhook.webhook_url(gateway)
    assert payload["secret_token"] == gateway.webhook_secret
    assert payload["allowed_updates"] == ["message", "callback_query"]
  end

  test "gateways appear under agents in the sidebar and can be enabled from the list", %{
    conn: conn,
    scope: scope
  } do
    stub_telegram_webhook(self())

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Telegram Intake",
        "type" => "telegram",
        "token" => "toggle-token",
        "status" => "inactive"
      })

    {:ok, live_view, _html} = live(conn, ~p"/gateways")

    assert has_element?(live_view, "#sidebar-agents-group #sidebar-gateways-link", "Gateways")
    assert has_element?(live_view, "#gateway-switch-#{gateway.id}[role=\"switch\"]")

    live_view
    |> element("#gateway-switch-#{gateway.id}")
    |> render_click()

    reloaded_gateway = Gateways.get_gateway!(scope, gateway.id)
    assert reloaded_gateway.status == :active

    assert_received {:telegram_set_webhook, "/bottoggle-token/setWebhook", payload}
    assert payload["url"] == TelegramWebhook.webhook_url(reloaded_gateway)
  end

  defp stub_telegram_webhook(test_pid) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:telegram_set_webhook, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
    end)
  end
end
