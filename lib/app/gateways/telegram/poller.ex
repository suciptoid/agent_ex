defmodule App.Gateways.Telegram.Poller do
  @moduledoc false

  use GenServer

  require Logger

  alias App.Gateways
  alias App.Gateways.Gateway
  alias App.Gateways.Telegram.Client
  alias App.Gateways.Telegram.Handler
  alias App.Gateways.Telegram.Webhook

  @default_retry_ms 1_000
  @default_idle_ms 250
  @default_timeout_seconds 30

  def child_spec(opts) do
    gateway_id = Keyword.fetch!(opts, :gateway_id)

    %{
      id: {__MODULE__, gateway_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    gateway_id = Keyword.fetch!(opts, :gateway_id)
    GenServer.start_link(__MODULE__, %{gateway_id: gateway_id}, name: via(gateway_id))
  end

  def poll_once(gateway_or_id, offset \\ nil)

  def poll_once(%Gateway{} = gateway, offset) do
    if gateway.type != :telegram or gateway.status != :active or
         Webhook.update_mode(gateway) != :longpoll do
      {:stop, :inactive}
    else
      client = Client.new(gateway.token)

      params =
        %{
          timeout: timeout_seconds(),
          allowed_updates: Webhook.allowed_updates(gateway)
        }
        |> maybe_put_offset(offset)

      case Client.get_updates(client, params) do
        {:ok, %{"result" => updates}} when is_list(updates) ->
          next_offset = handle_updates(gateway, updates, offset)
          {:ok, next_offset, length(updates)}

        {:ok, body} ->
          {:error, {:unexpected_response, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def poll_once(gateway_id, offset) when is_binary(gateway_id) do
    case Gateways.get_gateway_by_id(gateway_id) do
      %Gateway{} = gateway -> poll_once(gateway, offset)
      nil -> {:stop, :not_found}
    end
  end

  @impl true
  def init(state) do
    send(self(), :poll)
    {:ok, Map.put(state, :offset, nil)}
  end

  @impl true
  def handle_info(:poll, %{gateway_id: gateway_id, offset: offset} = state) do
    case poll_once(gateway_id, offset) do
      {:ok, next_offset, processed_count} ->
        schedule_poll(processed_count)
        {:noreply, %{state | offset: next_offset}}

      {:stop, reason} ->
        Logger.info("Stopping Telegram longpoll worker for #{gateway_id}: #{inspect(reason)}")
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.warning("Telegram longpoll failed for #{gateway_id}: #{inspect(reason)}")
        Process.send_after(self(), :poll, retry_ms())
        {:noreply, state}
    end
  end

  defp handle_updates(gateway, updates, current_offset) do
    Enum.reduce(updates, current_offset, fn update, offset ->
      safely_handle_update(gateway, update)

      case Map.get(update, "update_id") do
        update_id when is_integer(update_id) -> update_id + 1
        _other -> offset
      end
    end)
  end

  defp safely_handle_update(gateway, update) do
    Handler.handle_update(gateway, update)
  rescue
    error ->
      Logger.error("Telegram longpoll update handling failed: #{Exception.message(error)}")
  end

  defp maybe_put_offset(params, nil), do: params
  defp maybe_put_offset(params, offset), do: Map.put(params, :offset, offset)

  defp schedule_poll(0), do: Process.send_after(self(), :poll, idle_ms())
  defp schedule_poll(_processed_count), do: send(self(), :poll)

  defp retry_ms do
    Application.get_env(:app, __MODULE__, [])
    |> Keyword.get(:retry_ms, @default_retry_ms)
  end

  defp idle_ms do
    Application.get_env(:app, __MODULE__, [])
    |> Keyword.get(:idle_ms, @default_idle_ms)
  end

  defp timeout_seconds do
    Application.get_env(:app, __MODULE__, [])
    |> Keyword.get(:timeout_seconds, @default_timeout_seconds)
  end

  defp via(gateway_id) do
    {:via, Registry, {App.Gateways.Telegram.PollerRegistry, gateway_id}}
  end
end
