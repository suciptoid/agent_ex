defmodule App.Gateways.Telegram.Client do
  @moduledoc """
  Telegram Bot API client using Req.
  """

  @markdown_v2_entity_error "can't parse entities"

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

  def send_markdown_message(client, chat_id, text, extra \\ %{}) do
    params = Map.merge(%{chat_id: chat_id, text: text, parse_mode: "MarkdownV2"}, extra)

    case request(client, "sendMessage", params) do
      {:error, {:telegram_api_error, 400, body}} = error ->
        if markdown_v2_entity_error?(body) do
          params
          |> Map.put(:text, escape_markdown_v2(text))
          |> then(&request(client, "sendMessage", &1))
        else
          error
        end

      result ->
        result
    end
  end

  def send_chat_action(client, chat_id, action \\ "typing") do
    request(client, "sendChatAction", %{chat_id: chat_id, action: action})
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

  defp escape_markdown_v2(text) when is_binary(text) do
    Regex.replace(~r/([_*\[\]()~`>#+\-=|{}.!\\])/u, text, fn _, char -> "\\" <> char end)
  end

  defp escape_markdown_v2(text), do: text

  defp markdown_v2_entity_error?(%{"description" => description}) when is_binary(description) do
    String.contains?(description, @markdown_v2_entity_error)
  end

  defp markdown_v2_entity_error?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"description" => description}} when is_binary(description) ->
        String.contains?(description, @markdown_v2_entity_error)

      _other ->
        String.contains?(body, @markdown_v2_entity_error)
    end
  end

  defp markdown_v2_entity_error?(_body), do: false
end
