defmodule App.Gateways.Telegram.ClientTest do
  use ExUnit.Case, async: false

  alias App.Gateways.Telegram.Client

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

  test "normalizes common double-asterisk bold into Telegram bold" do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:telegram_request, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, ~s({"ok":true,"result":true}))
    end)

    assert {:ok, _response} =
             Client.send_markdown_message(Client.new("telegram-token"), 1234, "**Harga Bitcoin**")

    assert_receive {:telegram_request, "/bottelegram-token/sendMessage", payload}
    assert payload["chat_id"] == 1234
    assert payload["parse_mode"] == "MarkdownV2"
    assert payload["text"] == "*Harga Bitcoin*"
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:app, key)
  defp restore_app_env(key, value), do: Application.put_env(:app, key, value)
end
