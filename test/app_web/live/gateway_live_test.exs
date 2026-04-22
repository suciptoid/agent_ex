defmodule AppWeb.GatewayLiveTest do
  use AppWeb.ConnCase, async: false

  alias App.Gateways
  alias App.Gateways.Telegram.Webhook, as: TelegramWebhook

  import App.AgentsFixtures
  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  setup do
    previous_config = Application.get_env(:app, App.Gateways.Telegram.Client)
    previous_runtime_config = Application.get_env(:app, App.Gateways.Telegram.Runtime)

    Application.put_env(:app, App.Gateways.Telegram.Client,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    Application.put_env(:app, App.Gateways.Telegram.Runtime, auto_start?: false)

    on_exit(fn ->
      if previous_config do
        Application.put_env(:app, App.Gateways.Telegram.Client, previous_config)
      else
        Application.delete_env(:app, App.Gateways.Telegram.Client)
      end

      if previous_runtime_config do
        Application.put_env(:app, App.Gateways.Telegram.Runtime, previous_runtime_config)
      else
        Application.delete_env(:app, App.Gateways.Telegram.Runtime)
      end
    end)

    :ok
  end

  test "new gateway form saves active telegram gateways and registers a webhook", %{
    conn: conn,
    user: user,
    scope: scope
  } do
    primary_agent = agent_fixture(user, %{name: "Telegram Support"})
    backup_agent = agent_fixture(user, %{name: "Telegram Backup"})
    stub_telegram_webhook(self())

    {:ok, index_view, _html} = live(conn, ~p"/gateways")

    assert {:error, {:live_redirect, %{to: to}}} =
             index_view
             |> element("#new-gateway-button")
             |> render_click()

    assert to == "/gateways/new"

    {:ok, live_view, _html} = live(conn, ~p"/gateways/new")

    assert has_element?(live_view, "#gateway-form-page")
    assert has_element?(live_view, "#gateway-form")
    refute has_element?(live_view, "#gateway-dialog")
    assert has_element?(live_view, "a", "Back to gateways")
    assert render(live_view) =~ "disable BotFather privacy mode"

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

    _ =
      live_view
      |> element("#gateway-form")
      |> render_change(%{"gateway" => %{"type" => "telegram"}})

    assert has_element?(
             live_view,
             "#gateway-form [role=\"option\"][data-value=\"webhook\"]",
             "Webhook"
           )

    assert has_element?(
             live_view,
             "#gateway-form [role=\"option\"][data-value=\"longpoll\"]",
             "Long Polling"
           )

    assert has_element?(
             live_view,
             "#gateway-form [role=\"option\"][data-value=\"#{primary_agent.id}\"]",
             "Telegram Support"
           )

    assert has_element?(
             live_view,
             "#gateway-form input[type=\"checkbox\"][name=\"gateway[config][agent_ids][]\"][value=\"#{primary_agent.id}\"]"
           )

    assert has_element?(
             live_view,
             "#gateway-form input[type=\"hidden\"][name=\"gateway[config][allow_all_users]\"][value=\"false\"]"
           )

    assert has_element?(
             live_view,
             "#gateway-form input[type=\"checkbox\"][name=\"gateway[config][allow_all_users]\"][value=\"true\"]"
           )

    submit_result =
      live_view
      |> element("#gateway-form")
      |> render_submit(%{
        "gateway" => %{
          "name" => "Support Bot",
          "type" => "telegram",
          "token" => "123456:telegram-bot-token",
          "status" => "active",
          "config" => %{
            "agent_ids" => [primary_agent.id, backup_agent.id],
            "agent_id" => backup_agent.id,
            "allow_all_users" => "false",
            "welcome_message" => "Hello from Telegram"
          }
        }
      })

    assert_redirect(live_view, ~p"/gateways")

    [gateway] = Gateways.list_gateways(scope)

    {:ok, redirected_view, _html} = follow_redirect(submit_result, conn, ~p"/gateways")

    assert gateway.name == "Support Bot"
    assert gateway.type == :telegram
    assert gateway.status == :active
    assert Enum.sort(gateway.config.agent_ids) == Enum.sort([primary_agent.id, backup_agent.id])
    assert gateway.config.agent_id == backup_agent.id
    assert gateway.config.allow_all_users == false
    assert gateway.config.welcome_message == "Hello from Telegram"
    assert has_element?(redirected_view, "#edit-gateway-#{gateway.id}")

    assert_received {:telegram_set_webhook, "/bot123456:telegram-bot-token/setWebhook", payload}
    assert payload["url"] == TelegramWebhook.webhook_url(gateway)
    assert payload["secret_token"] == gateway.webhook_secret
    assert payload["allowed_updates"] == ["message", "callback_query"]
  end

  test "new telegram longpoll gateway saves without registering a webhook", %{
    conn: conn,
    scope: scope
  } do
    stub_telegram_api(self())

    {:ok, live_view, _html} = live(conn, ~p"/gateways/new")

    submit_result =
      live_view
      |> element("#gateway-form")
      |> render_submit(%{
        "gateway" => %{
          "name" => "Polling Bot",
          "type" => "telegram",
          "token" => "123456:polling-bot-token",
          "status" => "active",
          "config" => %{
            "update_mode" => "longpoll"
          }
        }
      })

    assert_redirect(live_view, ~p"/gateways")
    {:ok, _redirected_view, _html} = follow_redirect(submit_result, conn, ~p"/gateways")

    [gateway] = Gateways.list_gateways(scope)
    assert gateway.config.update_mode == :longpoll

    assert_received {:telegram_delete_webhook, "/bot123456:polling-bot-token/deleteWebhook",
                     payload}

    assert payload["drop_pending_updates"] == false
    refute_received {:telegram_set_webhook, _, _}
  end

  test "edit gateway opens as a dedicated page and saves changes", %{conn: conn, scope: scope} do
    stub_telegram_webhook(self())

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Ops Bot",
        "type" => "telegram",
        "token" => "ops-token",
        "status" => "inactive"
      })

    {:ok, index_view, _html} = live(conn, ~p"/gateways")

    assert {:error, {:live_redirect, %{to: to}}} =
             index_view
             |> element("#edit-gateway-#{gateway.id}")
             |> render_click()

    assert to == "/gateways/#{gateway.id}/edit"

    {:ok, live_view, _html} = live(conn, ~p"/gateways/#{gateway.id}/edit")

    assert has_element?(live_view, "#gateway-form-page")
    refute has_element?(live_view, "#gateway-dialog")

    submit_result =
      live_view
      |> element("#gateway-form")
      |> render_submit(%{
        "gateway" => %{
          "name" => "Ops Bot Updated",
          "type" => "telegram",
          "token" => "ops-token",
          "status" => "inactive",
          "config" => %{
            "allow_all_users" => "true",
            "welcome_message" => "Hello team"
          }
        }
      })

    assert_redirect(live_view, ~p"/gateways")
    assert Gateways.get_gateway!(scope, gateway.id).name == "Ops Bot Updated"
    {:ok, _redirected_view, _html} = follow_redirect(submit_result, conn, ~p"/gateways")
  end

  test "gateways appear under agents in the sidebar with consistent nav styling and can be enabled from the list",
       %{
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
    assert has_element?(live_view, "#sidebar-gateways-link.rounded-lg")
    assert has_element?(live_view, "#sidebar-gateways-link .size-4\\.5")
    refute has_element?(live_view, "#sidebar-gateways-link.text-muted-foreground")
    assert has_element?(live_view, "#gateway-switch-#{gateway.id}[role=\"switch\"]")

    live_view
    |> element("#gateway-switch-#{gateway.id}")
    |> render_click()

    reloaded_gateway = Gateways.get_gateway!(scope, gateway.id)
    assert reloaded_gateway.status == :active

    assert_received {:telegram_set_webhook, "/bottoggle-token/setWebhook", payload}
    assert payload["url"] == TelegramWebhook.webhook_url(reloaded_gateway)
  end

  defp stub_telegram_webhook(test_pid), do: stub_telegram_api(test_pid)

  defp stub_telegram_api(test_pid) do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = if body == "", do: %{}, else: Jason.decode!(body)

      case conn.request_path do
        path ->
          cond do
            String.ends_with?(path, "/setWebhook") ->
              send(test_pid, {:telegram_set_webhook, path, payload})
              Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))

            String.ends_with?(path, "/deleteWebhook") ->
              send(test_pid, {:telegram_delete_webhook, path, payload})
              Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))

            String.ends_with?(path, "/getUpdates") ->
              send(test_pid, {:telegram_get_updates, path, payload})
              Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":[]}))

            true ->
              Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
          end
      end
    end)
  end
end
