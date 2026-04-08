defmodule App.Gateways.Telegram.Webhook do
  @moduledoc false

  import Ecto.Changeset, only: [change: 2]

  alias App.Gateways.Gateway
  alias App.Gateways.Gateway.Config
  alias App.Gateways.Telegram.Client
  alias App.Repo

  def sync(%Gateway{type: :telegram, status: :active} = gateway) do
    params = %{
      secret_token: gateway.webhook_secret,
      allowed_updates: allowed_updates(gateway)
    }

    case Client.set_webhook(Client.new(gateway.token), webhook_url(gateway), params) do
      {:ok, _body} ->
        {:ok, gateway}

      {:error, reason} ->
        mark_sync_error(gateway, reason)
    end
  end

  def sync(%Gateway{} = gateway), do: {:ok, gateway}

  def webhook_url(%Gateway{id: id}) do
    "#{AppWeb.Endpoint.url()}/gateway/webhook/#{id}"
  end

  defp allowed_updates(%Gateway{config: %Config{allowed_updates: updates}})
       when is_list(updates) do
    updates
  end

  defp allowed_updates(%Gateway{config: %{} = config}) do
    Map.get(config, :allowed_updates) || Map.get(config, "allowed_updates") || default_updates()
  end

  defp allowed_updates(_gateway), do: default_updates()

  defp default_updates, do: ["message", "callback_query"]

  defp mark_sync_error(%Gateway{} = gateway, reason) do
    case Repo.update(change(gateway, status: :error)) do
      {:ok, gateway} ->
        {:error, gateway, error_message(reason)}

      {:error, _changeset} ->
        {:error, %{gateway | status: :error}, error_message(reason)}
    end
  end

  defp error_message({:telegram_api_error, _status, %{"description" => description}}),
    do: description

  defp error_message({:telegram_api_error, status, body}),
    do: "Telegram API returned #{status}: #{inspect(body)}"

  defp error_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp error_message(reason), do: inspect(reason)
end
