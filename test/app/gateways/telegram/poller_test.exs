defmodule App.Gateways.Telegram.PollerTest do
  use App.DataCase, async: false

  alias App.Gateways
  alias App.Gateways.Telegram.Poller

  import App.OrganizationsFixtures

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

  test "poll_once pulls Telegram updates and advances the offset" do
    user = App.UsersFixtures.user_fixture()
    organization = organization_fixture(user)
    scope = organization_scope_fixture(user, organization: organization)
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = if body == "", do: %{}, else: Jason.decode!(body)

      case conn.request_path do
        path ->
          cond do
            String.ends_with?(path, "/getUpdates") ->
              send(test_pid, {:telegram_get_updates, path, payload})

              Req.Test.json(conn, %{
                ok: true,
                result: [
                  %{
                    update_id: 100,
                    message: %{
                      message_id: 1,
                      date: 1_710_000_000,
                      text: "/start",
                      chat: %{id: 1234, type: "private", username: "poller_user"},
                      from: %{id: 5678, first_name: "Poller", username: "poller_user"}
                    }
                  }
                ]
              })

            String.ends_with?(path, "/sendMessage") ->
              send(test_pid, {:telegram_send_message, path, payload})
              Req.Test.json(conn, %{ok: true, result: %{message_id: 10}})

            true ->
              Req.Test.json(conn, %{ok: true, result: true})
          end
      end
    end)

    {:ok, gateway} =
      Gateways.create_gateway(scope, %{
        "name" => "Polling Bot",
        "type" => "telegram",
        "token" => "poller-token",
        "status" => "active",
        "config" => %{
          "update_mode" => "longpoll",
          "welcome_message" => "Connected through polling."
        }
      })

    assert {:ok, 101, 1} = Poller.poll_once(gateway.id, nil)

    assert_received {:telegram_get_updates, "/botpoller-token/getUpdates", payload}
    assert payload["timeout"] == 30
    assert payload["allowed_updates"] == ["message", "callback_query"]
    refute Map.has_key?(payload, "offset")

    assert_received {:telegram_send_message, "/botpoller-token/sendMessage", send_payload}
    assert send_payload["chat_id"] == 1234
    assert send_payload["text"] == "Connected through polling."

    [channel] = Gateways.list_channels(gateway)
    assert channel.external_chat_id == "1234"
    assert channel.external_user_id == "5678"
    assert channel.approval_status == :pending_approval
  end
end
