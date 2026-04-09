defmodule App.Gateways.Telegram.ClientTest do
  use ExUnit.Case, async: false

  alias App.Gateways.Telegram.Client

  import ExUnit.CaptureLog

  setup do
    previous_config = Application.get_env(:app, Client)

    Application.put_env(:app, Client, req_options: [plug: {Req.Test, __MODULE__}])

    on_exit(fn ->
      restore_app_env(Client, previous_config)
    end)

    :ok
  end

  test "converts markdown tables into readable plain text before sending" do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:telegram_request, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
    end)

    content = """
    **Harga Bitcoin (BTC) / IDR**

    | Tanggal (WIB) | Harga ≈ (IDR) |
    |---------------|---------------|
    | Hari ini (9 April 2026) | **1 210 076 129** |
    | Kemarin (8 April 2026) | **≈ 1 191 000 000 - 1 200 000 000** |
    """

    assert {:ok, _response} =
             Client.send_markdown_message(Client.new("telegram-token"), 1234, content)

    assert_receive {:telegram_request, "/bottelegram-token/sendMessage", payload}
    assert payload["chat_id"] == 1234
    refute Map.has_key?(payload, "parse_mode")
    refute String.contains?(payload["text"], "|")
    refute String.contains?(payload["text"], "**")
    assert String.contains?(payload["text"], "Harga Bitcoin (BTC) / IDR")
    assert String.contains?(payload["text"], "• Tanggal (WIB): Hari ini (9 April 2026)")
    assert String.contains?(payload["text"], "Harga ≈ (IDR): 1 210 076 129")
  end

  test "preserves Telegram bold while escaping surrounding punctuation" do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:telegram_request, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
    end)

    assert {:ok, _response} =
             Client.send_markdown_message(
               Client.new("telegram-token"),
               1234,
               "Harga Bitcoin (BTC) terhadap Dolar Amerika (USD) hari ini: **$70 993** per BTC. 🚀"
             )

    assert_receive {:telegram_request, "/bottelegram-token/sendMessage", payload}
    assert payload["chat_id"] == 1234
    assert payload["parse_mode"] == "MarkdownV2"

    assert payload["text"] ==
             "Harga Bitcoin \\(BTC\\) terhadap Dolar Amerika \\(USD\\) hari ini: *$70 993* per BTC\\. 🚀"
  end

  test "logs a warning and falls back to plain text when Telegram still rejects markdown" do
    test_pid = self()
    attempt_counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      attempt =
        Agent.get_and_update(attempt_counter, fn current_attempt ->
          next_attempt = current_attempt + 1
          {next_attempt, next_attempt}
        end)

      send(test_pid, {:telegram_request_attempt, attempt, conn.request_path, payload})

      if attempt == 1 do
        Plug.Conn.send_resp(
          conn,
          400,
          ~s({"ok":false,"error_code":400,"description":"Bad Request: can't parse entities: Character '.' is reserved and must be escaped with the preceding '\\\\'"})
        )
      else
        Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
      end
    end)

    log =
      capture_log(fn ->
        assert {:ok, _response} =
                 Client.send_markdown_message(
                   Client.new("telegram-token"),
                   1234,
                   "*$70 993* per BTC."
                 )
      end)

    assert log =~ "Telegram rejected MarkdownV2 payload, falling back to plain text"

    assert_receive {:telegram_request_attempt, 1, "/bottelegram-token/sendMessage", first_payload}
    assert first_payload["parse_mode"] == "MarkdownV2"

    assert_receive {:telegram_request_attempt, 2, "/bottelegram-token/sendMessage",
                    second_payload}

    refute Map.has_key?(second_payload, "parse_mode")
    assert second_payload["text"] == "$70 993 per BTC."
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:app, key)
  defp restore_app_env(key, value), do: Application.put_env(:app, key, value)
end
