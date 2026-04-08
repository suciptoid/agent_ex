defmodule AppWeb.GatewayWebhookController do
  use AppWeb, :controller

  require Logger

  alias App.Gateways
  alias App.Gateways.Gateway
  alias App.Gateways.Telegram.Handler, as: TelegramHandler

  def create(conn, %{"gateway_id" => gateway_id} = params) do
    with %Gateway{} = gateway <- Gateways.get_gateway_by_id(gateway_id),
         :ok <- verify_webhook_secret(conn, gateway) do
      dispatch_update(gateway, params)
      send_resp(conn, 200, "ok")
    else
      nil ->
        send_resp(conn, 404, "not found")

      :error ->
        send_resp(conn, 401, "unauthorized")
    end
  end

  defp verify_webhook_secret(conn, %Gateway{webhook_secret: secret}) do
    case get_req_header(conn, "x-telegram-bot-api-secret-token") do
      [^secret] -> :ok
      [] -> :ok
      _ -> :error
    end
  end

  defp dispatch_update(%Gateway{type: :telegram} = gateway, params) do
    Task.start(fn ->
      try do
        TelegramHandler.handle_update(gateway, params)
      rescue
        e ->
          Logger.error("Telegram handler error: #{Exception.message(e)}")
      end
    end)
  end

  defp dispatch_update(%Gateway{type: type}, _params) do
    Logger.info("No handler for gateway type: #{type}")
    :ok
  end
end
