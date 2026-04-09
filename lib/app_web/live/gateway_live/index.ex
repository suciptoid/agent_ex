defmodule AppWeb.GatewayLive.Index do
  use AppWeb, :live_view

  alias App.Gateways
  alias App.Gateways.Telegram.Webhook, as: TelegramWebhook
  alias App.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage?, Scope.manager?(socket.assigns.current_scope))
     |> stream(:gateways, Gateways.list_gateways(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Gateways")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if socket.assigns.can_manage? do
      gateway = Gateways.get_gateway!(socket.assigns.current_scope, id)
      {:ok, _} = Gateways.delete_gateway(socket.assigns.current_scope, gateway)
      {:noreply, stream_delete(socket, :gateways, gateway)}
    else
      {:noreply,
       put_flash(socket, :error, "Only organization owners and admins can manage gateways.")}
    end
  end

  def handle_event("toggle-status", %{"enabled" => enabled, "id" => id}, socket) do
    if socket.assigns.can_manage? do
      gateway = Gateways.get_gateway!(socket.assigns.current_scope, id)
      status = if enabled == "true", do: "active", else: "inactive"

      case Gateways.update_gateway(socket.assigns.current_scope, gateway, %{status: status}) do
        {:ok, gateway} ->
          {:noreply, sync_gateway_status(socket, gateway)}

        {:error, %Ecto.Changeset{}} ->
          {:noreply, put_flash(socket, :error, "Unable to update gateway status.")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Only organization owners and admins can manage gateways.")}
    end
  end

  defp gateway_type_label(:telegram), do: "Telegram Bot"
  defp gateway_type_label(:whatsapp_api), do: "WhatsApp API"
  defp gateway_type_label(type), do: to_string(type)

  defp gateway_type_icon(:telegram), do: "hero-paper-airplane"
  defp gateway_type_icon(:whatsapp_api), do: "hero-chat-bubble-left-right"
  defp gateway_type_icon(_), do: "hero-signal"

  defp gateway_type_bg(:telegram), do: "bg-blue-500"
  defp gateway_type_bg(:whatsapp_api), do: "bg-green-500"
  defp gateway_type_bg(_), do: "bg-gray-500"

  defp gateway_status_classes(:active),
    do: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400"

  defp gateway_status_classes(:inactive),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400"

  defp gateway_status_classes(:error),
    do: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400"

  defp gateway_status_classes(_), do: "bg-gray-100 text-gray-600"

  defp sync_gateway_status(socket, gateway) do
    case TelegramWebhook.sync(gateway) do
      {:ok, gateway} ->
        stream_insert(socket, :gateways, gateway)

      {:error, gateway, reason} ->
        socket
        |> put_flash(:error, "Telegram webhook registration failed: #{reason}")
        |> stream_insert(:gateways, gateway)
    end
  end
end
