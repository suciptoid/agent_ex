defmodule App.Gateways.Telegram.Client do
  @moduledoc """
  Telegram Bot API client using Req.
  """

  defstruct [:token, :base_url]

  def new(token, opts \\ []) do
    %__MODULE__{
      token: token,
      base_url: Keyword.get(opts, :base_url, "https://api.telegram.org")
    }
  end

  def request(%__MODULE__{} = client, method, params \\ %{}) do
    url = "#{client.base_url}/bot#{client.token}/#{method}"

    url
    |> Req.post(
      Keyword.merge(req_options(),
        json: params,
        receive_timeout: 15_000
      )
    )
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:telegram_api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_me(client), do: request(client, "getMe")

  def send_message(client, chat_id, text, extra \\ %{}) do
    params = Map.merge(%{chat_id: chat_id, text: text}, extra)
    request(client, "sendMessage", params)
  end

  def answer_callback_query(client, callback_query_id, extra \\ %{}) do
    params = Map.put(extra, :callback_query_id, callback_query_id)
    request(client, "answerCallbackQuery", params)
  end

  def set_webhook(client, url, extra \\ %{}) do
    params = Map.merge(%{url: url}, extra)
    request(client, "setWebhook", params)
  end

  def delete_webhook(client, extra \\ %{}) do
    request(client, "deleteWebhook", extra)
  end

  def get_webhook_info(client) do
    request(client, "getWebhookInfo")
  end

  def edit_message_text(client, chat_id, message_id, text, extra \\ %{}) do
    params = Map.merge(%{chat_id: chat_id, message_id: message_id, text: text}, extra)
    request(client, "editMessageText", params)
  end

  def delete_message(client, chat_id, message_id) do
    request(client, "deleteMessage", %{chat_id: chat_id, message_id: message_id})
  end

  defp req_options do
    Application.get_env(:app, __MODULE__, [])
    |> Keyword.get(:req_options, [])
  end
end
