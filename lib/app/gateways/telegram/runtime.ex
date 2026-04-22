defmodule App.Gateways.Telegram.Runtime do
  @moduledoc false

  use GenServer

  import Ecto.Query, warn: false

  alias App.Gateways.Gateway
  alias App.Gateways.Telegram.Poller
  alias App.Gateways.Telegram.Webhook
  alias App.Repo

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def auto_start? do
    Application.get_env(:app, __MODULE__, [])
    |> Keyword.get(:auto_start?, true)
  end

  def ensure_gateway(%Gateway{} = gateway) do
    if gateway.status == :active and Webhook.update_mode(gateway) == :longpoll do
      start_gateway(gateway)
    else
      stop_gateway(gateway)
    end
  end

  def start_gateway(%Gateway{id: gateway_id}) do
    child_spec = {Poller, gateway_id: gateway_id}

    case DynamicSupervisor.start_child(App.Gateways.Telegram.PollerSupervisor, child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, :already_present} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def stop_gateway(%Gateway{id: gateway_id}), do: stop_gateway(gateway_id)

  def stop_gateway(gateway_id) when is_binary(gateway_id) do
    case Registry.lookup(App.Gateways.Telegram.PollerRegistry, gateway_id) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(App.Gateways.Telegram.PollerSupervisor, pid)

      [] ->
        :ok
    end
  end

  @impl true
  def init(_opts) do
    if auto_start?() do
      send(self(), :bootstrap)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:bootstrap, state) do
    Gateway
    |> where([gateway], gateway.type == :telegram and gateway.status == :active)
    |> Repo.all()
    |> Enum.filter(&(Webhook.update_mode(&1) == :longpoll))
    |> Enum.each(&start_gateway/1)

    {:noreply, state}
  end
end
