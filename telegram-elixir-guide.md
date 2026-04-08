# Telegram Bot API with Phoenix Webhooks and Req in Elixir

This guide explains how to build a Telegram bot in Elixir using:

- **Phoenix** as the webhook HTTP server
- **Req** as the HTTP client for calling the Telegram Bot API

It is based on the Telegram Bot API documentation at `https://core.telegram.org/bots/api` and focuses on the practical parts you need for a production-ready bot.

---

## 1. What Telegram Bot API gives you

Telegram Bot API is an **HTTPS-based HTTP API**. You call methods like:

- `getMe`
- `sendMessage`
- `setWebhook`
- `deleteWebhook`
- `getWebhookInfo`
- `answerCallbackQuery`
- `editMessageText`

Telegram sends your bot incoming updates as JSON-encoded **Update** objects.

You can receive updates in two mutually exclusive ways:

1. `getUpdates` long polling
2. **Webhooks** (`setWebhook`)

For Phoenix, webhook mode is usually the right choice.

### Key webhook facts from the docs

- Telegram sends updates with an HTTPS `POST` request.
- Webhook responses should return a `2xx` status code.
- Telegram will retry failed deliveries.
- You can protect the webhook using `secret_token`.
- You can set `allowed_updates` to reduce noise.
- Webhooks and `getUpdates` cannot be used at the same time.

---

## 2. Recommended architecture

A simple and robust layout is:

- **Phoenix endpoint** receives incoming Telegram updates
- **Update handler** parses and routes the update
- **Bot API client** wraps Req calls for outbound Telegram requests
- **State store** persists user/session state if your bot needs conversation flow

Example flow:

1. Telegram sends an `Update` to `/telegram/webhook`
2. Phoenix verifies the secret token header
3. Phoenix parses JSON into a map/struct
4. Your handler dispatches by update type
5. Your bot uses Req to call `sendMessage`, `answerCallbackQuery`, etc.
6. Phoenix returns `200 OK` quickly

---

## 3. Project setup

### Mix dependencies

Add Phoenix and Req:

```elixir
# mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:plug_cowboy, "~> 2.7"},
    {:req, "~> 0.5"},
    {:jason, "~> 1.4"}
  ]
end
```

Then install:

```bash
mix deps.get
```

### Configuration

Store your bot token and webhook secret in environment variables.

```elixir
# config/runtime.exs
config :my_app,
  telegram_bot_token: System.fetch_env!("TELEGRAM_BOT_TOKEN"),
  telegram_webhook_secret: System.fetch_env!("TELEGRAM_WEBHOOK_SECRET"),
  telegram_webhook_url: System.get_env("TELEGRAM_WEBHOOK_URL")
```

A recommended webhook URL looks like:

```text
https://your-domain.com/telegram/webhook
```

---

## 4. Telegram API client with Req

Telegram API methods are called with URLs like:

```text
https://api.telegram.org/bot<token>/METHOD_NAME
```

Req works great for JSON APIs.

### A minimal Telegram client

```elixir
defmodule MyApp.Telegram.Client do
  @moduledoc false

  defstruct [:token, :base_url]

  def new(token) do
    %__MODULE__{
      token: token,
      base_url: "https://api.telegram.org"
    }
  end

  def request(client, method, params \\ %{}) do
    url = "#{client.base_url}/bot#{client.token}/#{method}"

    Req.post(url,
      json: params,
      receive_timeout: 15_000,
      finch_options: [pool_timeout: 5_000]
    )
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:telegram_http_error, status, body}}

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
end
```

### Notes

- Telegram accepts `GET` and `POST`, but `POST` with JSON is usually easiest.
- For file uploads, you’ll need multipart form data instead of JSON.
- Telegram API responses always contain:
  - `ok`
  - optionally `result`
  - optionally `description`
  - optionally `error_code`

---

## 5. Phoenix webhook endpoint

Telegram webhook updates are JSON payloads sent as `POST` requests.

### Router

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/telegram", MyAppWeb do
    pipe_through :api

    post "/webhook", TelegramWebhookController, :create
  end
end
```

### Controller

```elixir
defmodule MyAppWeb.TelegramWebhookController do
  use MyAppWeb, :controller

  alias MyApp.Telegram.Handler

  def create(conn, params) do
    verify_secret_token!(conn)
    Handler.handle_update(params)
    send_resp(conn, 200, "ok")
  end

  defp verify_secret_token!(conn) do
    expected = Application.fetch_env!(:my_app, :telegram_webhook_secret)

    case get_req_header(conn, "x-telegram-bot-api-secret-token") do
      [^expected] -> :ok
      _ -> raise "invalid Telegram secret token"
    end
  end
end
```

### Important webhook rules

- Return fast. Telegram expects a response quickly.
- Do not do heavy work inline in the request process.
- If processing may take time, delegate to a Task, Oban job, or GenServer.
- Telegram retries when it sees failures, so your handler should be **idempotent**.

---

## 6. Update handling

Telegram sends an `Update` object with at most one top-level update field present.

Common fields:

- `message`
- `edited_message`
- `callback_query`
- `inline_query`
- `my_chat_member`
- `chat_member`
- `shipping_query`
- `pre_checkout_query`
- `poll`
- `poll_answer`
- `chat_join_request`
- `message_reaction`
- `chat_boost`
- `managed_bot`

### Example dispatcher

```elixir
defmodule MyApp.Telegram.Handler do
  alias MyApp.Telegram.Client

  def handle_update(%{"message" => message}) do
    handle_message(message)
  end

  def handle_update(%{"callback_query" => callback_query}) do
    handle_callback_query(callback_query)
  end

  def handle_update(_other), do: :ok

  defp handle_message(%{"chat" => %{"id" => chat_id}, "text" => text}) do
    client = Client.new(Application.fetch_env!(:my_app, :telegram_bot_token))

    case String.trim(text) do
      "/start" ->
        Client.send_message(client, chat_id, "Welcome! Send /help for commands.")

      "/help" ->
        Client.send_message(client, chat_id, "Commands: /start, /help")

      other ->
        Client.send_message(client, chat_id, "You said: #{other}")
    end
  end

  defp handle_message(_), do: :ok

  defp handle_callback_query(%{"id" => id, "data" => data, "message" => %{"chat" => %{"id" => chat_id}}}) do
    client = Client.new(Application.fetch_env!(:my_app, :telegram_bot_token))

    with {:ok, _} <- Client.answer_callback_query(client, id, %{text: "Clicked: #{data}"}),
         {:ok, _} <- Client.send_message(client, chat_id, "Callback data: #{data}") do
      :ok
    end
  end

  defp handle_callback_query(_), do: :ok
end
```

---

## 7. Webhook registration at startup

When your app boots, it can register the webhook automatically.

### Suggested approach

- Start your application
- Read `TELEGRAM_WEBHOOK_URL`
- Call `setWebhook`
- Optionally verify with `getWebhookInfo`

```elixir
defmodule MyApp.Telegram.WebhookSetup do
  alias MyApp.Telegram.Client

  def ensure_webhook! do
    token = Application.fetch_env!(:my_app, :telegram_bot_token)
    url = Application.fetch_env!(:my_app, :telegram_webhook_url)
    secret = Application.fetch_env!(:my_app, :telegram_webhook_secret)

    client = Client.new(token)

    {:ok, _} =
      Client.set_webhook(client, url, %{
        secret_token: secret,
        drop_pending_updates: true,
        allowed_updates: [
          "message",
          "callback_query",
          "inline_query",
          "chat_member",
          "my_chat_member",
          "shipping_query",
          "pre_checkout_query"
        ]
      })

    :ok
  end
end
```

### Notes

- `drop_pending_updates: true` is useful on deploys if you do not want stale updates.
- `allowed_updates` reduces delivery volume.
- If you need to switch back to polling, call `deleteWebhook` first.

---

## 8. Handling callback buttons

Telegram inline keyboards are often the most useful way to build interactive bots.

### Example reply markup

```elixir
buttons = %{
  inline_keyboard: [
    [
      %{text: "Yes", callback_data: "yes"},
      %{text: "No", callback_data: "no"}
    ]
  ]
}

MyApp.Telegram.Client.send_message(client, chat_id, "Choose one:", %{reply_markup: buttons})
```

### Important callback query rule

Telegram clients display a progress indicator until your bot calls `answerCallbackQuery`. Even if you do not need to show a message, you should still answer the callback.

---

## 9. Formatting messages

Telegram supports formatting via:

- entities
- MarkdownV2
- HTML

### MarkdownV2 example

```elixir
Client.send_message(client, chat_id, "*Hello* _world_", %{parse_mode: "MarkdownV2"})
```

### HTML example

```elixir
Client.send_message(client, chat_id, "<b>Hello</b> <i>world</i>", %{parse_mode: "HTML"})
```

### Recommendation

For production bots, entities are safest if you generate dynamic content. MarkdownV2 requires heavy escaping.

---

## 10. Common outbound methods you’ll likely implement

Most bots only need a subset of the API.

### Essential methods

- `sendMessage`
- `sendPhoto`
- `sendDocument`
- `sendVideo`
- `sendSticker`
- `sendLocation`
- `editMessageText`
- `editMessageReplyMarkup`
- `deleteMessage`
- `answerCallbackQuery`
- `setWebhook`
- `deleteWebhook`
- `getWebhookInfo`
- `getMe`

### Example wrappers

```elixir
def send_photo(client, chat_id, photo, extra \\ %{}) do
  Client.request(client, "sendPhoto", Map.merge(%{chat_id: chat_id, photo: photo}, extra))
end

def edit_message_text(client, chat_id, message_id, text, extra \\ %{}) do
  params = Map.merge(%{chat_id: chat_id, message_id: message_id, text: text}, extra)
  Client.request(client, "editMessageText", params)
end

def delete_message(client, chat_id, message_id) do
  Client.request(client, "deleteMessage", %{chat_id: chat_id, message_id: message_id})
end
```

---

## 11. File uploads with Req

Telegram supports file sending via:

1. `file_id` from Telegram
2. remote URL
3. multipart upload

For multipart uploads, Req can send form data with files.

### Example: sendDocument with local file

```elixir
def send_document_file(client, chat_id, path) do
  url = "https://api.telegram.org/bot#{client.token}/sendDocument"

  Req.post(url,
    form: [
      chat_id: to_string(chat_id),
      document: Req.Multipart.Part.new_file("document", path)
    ]
  )
end
```

> Exact multipart handling may vary slightly depending on your Req version. If you need many uploads, it is worth wrapping this in a helper module and testing it with a real bot token.

---

## 12. Error handling strategy

Telegram errors typically look like:

```json
{
  "ok": false,
  "error_code": 400,
  "description": "Bad Request: chat not found"
}
```

### Recommended practices

- Log the method name and request payload, but avoid logging sensitive tokens.
- Handle common `400`, `403`, `429`, and `500` scenarios.
- Respect `retry_after` when Telegram rate-limits you.
- Make handler logic idempotent so repeated webhook deliveries are safe.

### Example retry handling for 429

```elixir
case Client.send_message(client, chat_id, "Hello") do
  {:ok, %{"ok" => true}} -> :ok
  {:error, {:telegram_http_error, 429, %{"parameters" => %{"retry_after" => retry_after}}}} ->
    Process.sleep(retry_after * 1000)
    Client.send_message(client, chat_id, "Hello")
  other -> other
end
```

---

## 13. Security checklist

Webhook bots should be treated as internet-facing systems.

### Always do these

- Use HTTPS only
- Verify `X-Telegram-Bot-Api-Secret-Token`
- Keep bot token in environment variables or a secrets manager
- Validate update payloads before using them
- Treat user-supplied text as untrusted
- Avoid putting secrets in logs
- Use rate limiting if your endpoint is public

### Optional but helpful

- IP allowlisting if you control the environment
- Reverse proxy protection
- Separate ingestion from processing via a job queue

---

## 14. Local development workflow

Telegram requires a public HTTPS URL for webhooks unless you use a local Bot API server.

### Good local options

- `ngrok`
- `cloudflared tunnel`
- a staging server

### Example workflow

1. Run Phoenix locally on `localhost:4000`
2. Start a tunnel to expose HTTPS
3. Set `TELEGRAM_WEBHOOK_URL` to the tunnel URL
4. Call `setWebhook`
5. Send a message to your bot in Telegram
6. Observe the Phoenix logs

---

## 15. Deployment tips

### Webhook-friendly deployment

Any platform that gives you a stable HTTPS endpoint will work:

- Fly.io
- Render
- Gigalixir
- Gigalixir-like Elixir platforms
- Kubernetes ingress
- VM behind Nginx/Caddy/Traefik

### Production tips

- Run at least one worker dedicated to your webhook endpoint
- Offload heavy bot logic to background jobs
- Store bot state in Postgres/Redis if you need conversations or deduplication
- Use telemetry and structured logs

---

## 16. Sample end-to-end setup

### Startup sequence

1. Phoenix boots
2. `WebhookSetup.ensure_webhook!/0` runs
3. Telegram starts delivering updates
4. Controller receives updates
5. Handler dispatches them
6. Req sends outbound API calls

### Minimal application start hook

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    Task.start(fn -> MyApp.Telegram.WebhookSetup.ensure_webhook!() end)

    {:ok, pid}
  end
end
```

---

## 17. Practical bot features to implement first

A solid first version usually includes:

- `/start` command
- `/help` command
- echo/reply behavior
- inline keyboard buttons
- callback query handling
- webhook registration and verification
- basic error logging
- a simple admin command or two

### Example command table

| Command | Behavior |
| --- | --- |
| `/start` | greet the user |
| `/help` | explain available commands |
| `/status` | return bot health or user-specific info |
| `/cancel` | exit a conversation |

---

## 18. Common Telegram object types you should know

The Bot API uses JSON objects for updates and payloads. The most common ones are:

- `Update`
- `Message`
- `User`
- `Chat`
- `CallbackQuery`
- `InlineKeyboardMarkup`
- `ReplyParameters`
- `MessageEntity`
- `WebhookInfo`
- `ChatMemberUpdated`
- `Poll`

For most bots, you can start by handling only:

- `message`
- `callback_query`
- `my_chat_member`

---

## 19. Recommended implementation pattern in Elixir

A clean structure is:

```text
lib/
  my_app/
    telegram/
      client.ex
      handler.ex
      webhook_setup.ex
      parser.ex
  my_app_web/
    controllers/
      telegram_webhook_controller.ex
```

### Responsibilities

- `client.ex` — low-level Telegram API calls via Req
- `handler.ex` — update routing and business logic
- `webhook_setup.ex` — webhook registration and health checks
- `telegram_webhook_controller.ex` — HTTP endpoint and verification

---

## 20. Example: read webhook status

Telegram’s `getWebhookInfo` is useful for debugging.

```elixir
{:ok, %{"ok" => true, "result" => info}} = MyApp.Telegram.Client.get_webhook_info(client)
IO.inspect(info, label: "WebhookInfo")
```

Look at fields such as:

- `url`
- `pending_update_count`
- `last_error_date`
- `last_error_message`
- `ip_address`
- `allowed_updates`

---

## 21. Production checklist

Before shipping, verify that you have:

- [ ] HTTPS webhook URL
- [ ] `setWebhook` configured
- [ ] webhook secret token verified
- [ ] `getWebhookInfo` checked
- [ ] message handlers implemented
- [ ] callback queries answered
- [ ] idempotency strategy in place
- [ ] rate limit and error handling
- [ ] file upload support if needed
- [ ] logs and alerts

---

## 22. Summary

Using Telegram Bot API with **Phoenix** and **Req** is straightforward:

- Phoenix handles incoming webhook requests
- Req handles outbound HTTP calls to Telegram
- The Bot API is JSON over HTTPS
- `setWebhook` is the key first step for webhook mode
- Keep webhook handlers fast, secure, and idempotent

If you only remember one thing: **return `200 OK` quickly and do the actual bot work in your application logic, not in the request cycle**.

---

## 23. Useful Telegram Bot API methods to bookmark

- `getMe`
- `setWebhook`
- `deleteWebhook`
- `getWebhookInfo`
- `sendMessage`
- `sendPhoto`
- `editMessageText`
- `answerCallbackQuery`
- `deleteMessage`
- `getFile`

