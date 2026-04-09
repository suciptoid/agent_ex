defmodule App.Gateways.Telegram.Client do
  @moduledoc """
  Telegram Bot API client using Req.
  """

  require Logger

  @markdown_v2_entity_error "can't parse entities"

  @sentinel_bold_open <<0xE000::utf8>>
  @sentinel_bold_close <<0xE001::utf8>>
  @sentinel_italic_open <<0xE002::utf8>>
  @sentinel_italic_close <<0xE003::utf8>>
  @sentinel_underline_open <<0xE004::utf8>>
  @sentinel_underline_close <<0xE005::utf8>>
  @sentinel_strike_open <<0xE006::utf8>>
  @sentinel_strike_close <<0xE007::utf8>>
  @sentinel_spoiler_open <<0xE008::utf8>>
  @sentinel_spoiler_close <<0xE009::utf8>>
  @sentinel_code_open <<0xE00A::utf8>>
  @sentinel_code_close <<0xE00B::utf8>>
  @sentinel_pre_open <<0xE00C::utf8>>
  @sentinel_pre_close <<0xE00D::utf8>>
  @sentinel_blockquote_open <<0xE00E::utf8>>

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
    text = normalize_telegram_markdown(text)

    if contains_markdown_table?(text) do
      extra
      |> Map.drop([:parse_mode, "parse_mode"])
      |> then(&send_message(client, chat_id, markdown_table_to_plain_text(text), &1))
    else
      formatted_text = sanitize_markdown_v2(text)

      params =
        Map.merge(%{chat_id: chat_id, text: formatted_text, parse_mode: "MarkdownV2"}, extra)

      case request(client, "sendMessage", params) do
        {:error, {:telegram_api_error, 400, body}} = error ->
          if markdown_v2_entity_error?(body) do
            Logger.warning(
              "Telegram rejected MarkdownV2 payload, falling back to plain text: #{markdown_error_description(body)}"
            )

            extra
            |> Map.drop([:parse_mode, "parse_mode"])
            |> then(&send_message(client, chat_id, strip_basic_markdown(text), &1))
          else
            error
          end

        result ->
          result
      end
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

  defp normalize_telegram_markdown(text) when is_binary(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace(~r/\*\*(.+?)\*\*/us, "*\\1*")
    |> String.replace(~r/^\s{0,3}\#{1,6}\s+(.+)$/m, "*\\1*")
    |> String.replace(~r/^(?:[-+*])\s+/m, "• ")
  end

  defp normalize_telegram_markdown(text), do: text

  defp sanitize_markdown_v2(text) when is_binary(text) do
    text
    |> preserve_preformatted_blocks()
    |> preserve_inline_code()
    |> preserve_spoilers()
    |> preserve_underline()
    |> preserve_bold()
    |> preserve_strikethrough()
    |> preserve_italic()
    |> preserve_blockquotes()
    |> escape_markdown_v2()
    |> restore_preserved_entities()
  end

  defp sanitize_markdown_v2(text), do: text

  defp contains_markdown_table?(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.chunk_by(&tableish_line?/1)
    |> Enum.any?(fn
      [line | rest] -> tableish_line?(line) and length([line | rest]) >= 2
      [] -> false
    end)
  end

  defp contains_markdown_table?(_text), do: false

  defp markdown_table_to_plain_text(text) do
    text
    |> String.split("\n")
    |> replace_table_blocks([], [])
    |> Enum.join("\n")
    |> strip_basic_markdown()
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

  defp markdown_error_description(%{"description" => description}) when is_binary(description),
    do: description

  defp markdown_error_description(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"description" => description}} when is_binary(description) -> description
      _other -> body
    end
  end

  defp markdown_error_description(body), do: inspect(body)

  defp preserve_preformatted_blocks(text) do
    Regex.replace(~r/```([A-Za-z0-9_+-]*)\n([\s\S]*?)```/u, text, fn _, language, body ->
      @sentinel_pre_open <> language <> "\n" <> body <> @sentinel_pre_close
    end)
  end

  defp preserve_inline_code(text) do
    Regex.replace(~r/`([^`\n]+)`/u, text, fn _, body ->
      @sentinel_code_open <> body <> @sentinel_code_close
    end)
  end

  defp preserve_spoilers(text) do
    Regex.replace(~r/\|\|(.+?)\|\|/us, text, fn _, body ->
      @sentinel_spoiler_open <> body <> @sentinel_spoiler_close
    end)
  end

  defp preserve_underline(text) do
    Regex.replace(~r/__([^\n].*?)__/us, text, fn _, body ->
      @sentinel_underline_open <> body <> @sentinel_underline_close
    end)
  end

  defp preserve_bold(text) do
    Regex.replace(~r/\*([^\s*](?:.*?[^\s*])?)\*/us, text, fn _, body ->
      @sentinel_bold_open <> body <> @sentinel_bold_close
    end)
  end

  defp preserve_strikethrough(text) do
    Regex.replace(~r/~([^\n].*?)~/us, text, fn _, body ->
      @sentinel_strike_open <> body <> @sentinel_strike_close
    end)
  end

  defp preserve_italic(text) do
    Regex.replace(~r/(?<!_)_([^\s_](?:.*?[^\s_])?)_(?!_)/us, text, fn _, body ->
      @sentinel_italic_open <> body <> @sentinel_italic_close
    end)
  end

  defp preserve_blockquotes(text) do
    Regex.replace(~r/^>\s?/m, text, @sentinel_blockquote_open)
  end

  defp restore_preserved_entities(text) do
    text
    |> String.replace(@sentinel_pre_open, "```")
    |> String.replace(@sentinel_pre_close, "```")
    |> String.replace(@sentinel_code_open, "`")
    |> String.replace(@sentinel_code_close, "`")
    |> String.replace(@sentinel_spoiler_open, "||")
    |> String.replace(@sentinel_spoiler_close, "||")
    |> String.replace(@sentinel_underline_open, "__")
    |> String.replace(@sentinel_underline_close, "__")
    |> String.replace(@sentinel_bold_open, "*")
    |> String.replace(@sentinel_bold_close, "*")
    |> String.replace(@sentinel_strike_open, "~")
    |> String.replace(@sentinel_strike_close, "~")
    |> String.replace(@sentinel_italic_open, "_")
    |> String.replace(@sentinel_italic_close, "_")
    |> String.replace(@sentinel_blockquote_open, ">")
  end

  defp replace_table_blocks([], [], acc), do: acc
  defp replace_table_blocks([], table_block, acc), do: acc ++ render_table_block(table_block)

  defp replace_table_blocks([line | rest], table_block, acc) do
    cond do
      tableish_line?(line) ->
        replace_table_blocks(rest, table_block ++ [line], acc)

      table_block == [] ->
        replace_table_blocks(rest, [], acc ++ [line])

      true ->
        replace_table_blocks(rest, [], acc ++ render_table_block(table_block) ++ [line])
    end
  end

  defp render_table_block(lines) do
    rows =
      lines
      |> Enum.reject(&separator_row?/1)
      |> Enum.map(&parse_table_row/1)
      |> Enum.reject(&(&1 == []))

    case rows do
      [headers | data_rows] when data_rows != [] ->
        data_rows
        |> Enum.flat_map(fn row ->
          headers
          |> Enum.with_index()
          |> Enum.map(fn {header, index} ->
            "#{header}: #{Enum.at(row, index, "") |> String.trim()}"
          end)
          |> Enum.reject(&String.ends_with?(&1, ": "))
          |> bulletize_pairs()
        end)
        |> trim_trailing_blank_lines()

      _other ->
        lines
    end
  end

  defp bulletize_pairs([]), do: []

  defp bulletize_pairs([first | rest]) do
    ["• " <> first] ++ Enum.map(rest, &("  " <> &1)) ++ [""]
  end

  defp trim_trailing_blank_lines(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  defp tableish_line?(line) when is_binary(line) do
    trimmed = String.trim(line)

    String.starts_with?(trimmed, "|") and String.ends_with?(trimmed, "|") and
      String.contains?(String.trim(trimmed, "|"), "|")
  end

  defp tableish_line?(_line), do: false

  defp separator_row?(line) do
    line
    |> parse_table_row()
    |> case do
      [] ->
        false

      cells ->
        Enum.all?(cells, &Regex.match?(~r/^:?-{3,}:?$/, &1))
    end
  end

  defp parse_table_row(line) do
    line
    |> String.trim()
    |> String.trim_leading("|")
    |> String.trim_trailing("|")
    |> String.split("|")
    |> Enum.map(&String.trim/1)
  end

  defp strip_basic_markdown(text) do
    text
    |> String.replace(~r/\[([^\]]+)\]\(([^)]+)\)/u, "\\1: \\2")
    |> String.replace(~r/[*_`~]/u, "")
    |> String.replace(~r/^\s{0,3}> ?/m, "")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end
end
