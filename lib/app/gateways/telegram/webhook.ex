defmodule App.Gateways.Telegram.Webhook do
  @moduledoc false

  import Ecto.Changeset, only: [change: 2]

  alias App.Gateways.Gateway
  alias App.Gateways.Gateway.Config
  alias App.Gateways.Telegram.Client
  alias App.Gateways.Telegram.Runtime
  alias App.Repo

  def sync(%Gateway{type: :telegram, status: :active} = gateway) do
    case update_mode(gateway) do
      :webhook ->
        with :ok <- Runtime.stop_gateway(gateway),
             {:ok, _body} <-
               Client.set_webhook(Client.new(gateway.token), webhook_url(gateway), %{
                 secret_token: gateway.webhook_secret,
                 allowed_updates: allowed_updates(gateway)
               }) do
          {:ok, gateway}
        else
          {:error, reason} -> mark_sync_error(gateway, reason)
        end

      :longpoll ->
        with {:ok, _body} <-
               Client.delete_webhook(Client.new(gateway.token), %{
                 drop_pending_updates: false
               }),
             :ok <- maybe_start_runtime_gateway(gateway) do
          {:ok, gateway}
        else
          {:error, reason} -> mark_sync_error(gateway, reason)
        end
    end
  end

  def sync(%Gateway{type: :telegram} = gateway) do
    with :ok <- Runtime.stop_gateway(gateway),
         {:ok, _body} <-
           Client.delete_webhook(Client.new(gateway.token), %{drop_pending_updates: false}) do
      {:ok, gateway}
    else
      {:error, reason} -> mark_sync_error(gateway, reason)
    end
  end

  def sync(%Gateway{} = gateway), do: {:ok, gateway}

  def webhook_url(%Gateway{id: id}) do
    "#{AppWeb.Endpoint.url()}/gateway/webhook/#{id}"
  end

  def allowed_updates(%Gateway{config: %Config{allowed_updates: updates}})
      when is_list(updates) do
    updates
  end

  def allowed_updates(%Gateway{config: %{} = config}) do
    Map.get(config, :allowed_updates) || Map.get(config, "allowed_updates") || default_updates()
  end

  def allowed_updates(_gateway), do: default_updates()

  def update_mode(%Gateway{config: %Config{update_mode: mode}})
      when mode in [:webhook, :longpoll],
      do: mode

  def update_mode(%Gateway{config: %{} = config}) do
    config
    |> Map.get(:update_mode, Map.get(config, "update_mode", :webhook))
    |> normalize_update_mode()
  end

  def update_mode(_gateway), do: :webhook

  defp default_updates, do: ["message", "callback_query"]

  defp maybe_start_runtime_gateway(gateway) do
    if Runtime.auto_start?() do
      Runtime.ensure_gateway(gateway)
    else
      :ok
    end
  end

  defp normalize_update_mode(mode) when mode in [:webhook, :longpoll], do: mode
  defp normalize_update_mode("longpoll"), do: :longpoll
  defp normalize_update_mode(_mode), do: :webhook

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
