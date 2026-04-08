# Gateway & Channel System

## Problem

We need a **gateway system** that bridges external messaging platforms (Telegram, WhatsApp, Discord, etc.) into our app's chat system. Each gateway connects to a provider (e.g., a Telegram bot) and exposes a webhook endpoint. When users send messages through these platforms, the system creates **channels** (mappings from provider conversations to our chat rooms) and routes messages to/from agents.

## Architecture Overview

```
External Platform → Webhook Endpoint → Gateway → Channel → ChatRoom → Agent
                                         ↑                      ↓
                                    (token/config)          (response)
                                         ↓                      ↓
External Platform ← Platform API ← Gateway ← Channel ← ChatRoom ← Agent
```

### Key Concepts

- **Gateway** (`App.Gateways.Gateway`): Represents a connection to an external messaging platform. Stores encrypted token, type (`:telegram`, `:whatsapp_api`), and configuration. Belongs to an organization. Exposes a webhook at `/gateway/webhook/:gateway_id`.
- **Channel** (`App.Gateways.Channel`): Maps an external conversation (e.g., a Telegram chat) to an internal `ChatRoom`. Created automatically when a new external conversation starts with a gateway. Contains access control (allowlist or allow-all).
- **Telegram Client** (`App.Gateways.Telegram.Client`): Wraps Req calls for Telegram Bot API.

## Data Model

### `gateways` table

| Column | Type | Notes |
|--------|------|-------|
| id | binary_id (PK) | |
| name | string | Human-friendly label |
| type | string (enum) | `telegram`, `whatsapp_api` |
| token | encrypted binary | Bot token (Telegram) / Access token (WhatsApp) |
| webhook_secret | string | Secret for webhook verification |
| config | embedded schema | Dynamic config (allowed_updates, agent_id for new channels, allow_all_users, allowed_user_ids, etc.) |
| status | string (enum) | `active`, `inactive`, `error` |
| organization_id | binary_id (FK) | |
| timestamps | | |

### `gateway_channels` table

| Column | Type | Notes |
|--------|------|-------|
| id | binary_id (PK) | |
| external_chat_id | string | Platform-specific chat identifier (Telegram chat_id, etc.) |
| external_user_id | string | Platform user who initiated |
| external_username | string | Display name from platform |
| status | string (enum) | `active`, `closed`, `blocked` |
| metadata | map | Extra platform-specific data |
| gateway_id | binary_id (FK) | |
| chat_room_id | binary_id (FK) | The internal ChatRoom this channel maps to |
| timestamps | | |
| unique index on (gateway_id, external_chat_id) | | |

### Gateway config embedded schema

```elixir
embedded_schema do
  field :agent_id, :binary_id          # Default agent for new channels
  field :allow_all_users, :boolean     # If true, any user can create a channel
  field :allowed_user_ids, {:array, :string}  # Allowlist of external user IDs
  field :welcome_message, :string      # Sent on /start or new channel
  field :allowed_updates, {:array, :string}   # Telegram-specific
end
```

## Implementation Phases

### Phase 1: Schema & Context (Foundation)

1. **Migration**: Create `gateways` and `gateway_channels` tables
2. **Schema**: `App.Gateways.Gateway` with embedded `Config` schema, encrypted token via `App.Encrypted.Binary`
3. **Schema**: `App.Gateways.Channel` linking external chats to internal `ChatRoom`
4. **Context**: `App.Gateways` — CRUD for gateways & channels, access control checks
5. **Organization association**: Add `has_many :gateways` to Organization schema

### Phase 2: Telegram Client & Webhook

6. **Telegram Client**: `App.Gateways.Telegram.Client` — Req-based API client (sendMessage, setWebhook, getMe, etc.)
7. **Webhook Controller**: `AppWeb.GatewayWebhookController` — receives POST at `/gateway/webhook/:gateway_id`, verifies secret, dispatches to handler
8. **Router**: Add webhook route under `:api` pipeline (no CSRF, no session needed)

### Phase 3: Message Handling & Channel Creation

9. **Telegram Handler**: `App.Gateways.Telegram.Handler` — parses Telegram updates, creates channels on first contact, routes messages to ChatRoom
10. **Channel creation logic**: Check allowlist, create ChatRoom + Channel, assign configured agent
11. **Inbound flow**: Telegram message → Handler → find/create Channel → create Message in ChatRoom → trigger agent stream
12. **Outbound flow**: Subscribe to ChatRoom broadcasts → send assistant replies back via Telegram Client

### Phase 4: Gateway Management UI (LiveView)

13. **Gateway LiveView**: CRUD interface for managing gateways (inside `:require_active_organization` live_session)
14. **Webhook setup**: Button/action to register webhook with Telegram via `setWebhook`
15. **Channel list**: View channels associated with a gateway

### Phase 5: Testing

16. **Context tests**: `App.Gateways` context tests
17. **Controller tests**: Webhook endpoint tests with mock payloads
18. **Integration tests**: End-to-end message flow tests

## File Structure

```
lib/app/gateways/
  gateway.ex           # Schema + embedded Config
  channel.ex           # Schema
  telegram/
    client.ex          # Req-based Telegram API client
    handler.ex         # Update parser & dispatcher
lib/app/gateways.ex    # Context module
lib/app_web/
  controllers/
    gateway_webhook_controller.ex
  live/
    gateway_live/
      index.ex         # List/manage gateways
      form.ex          # Create/edit gateway form
```

## Notes

- Token encryption uses existing `App.Encrypted.Binary` (Cloak) — same pattern as Provider `api_key`
- Webhook secret is auto-generated per gateway (used for Telegram `secret_token` header verification)
- Channel creation is gated by gateway config: either `allow_all_users: true` or external user must be in `allowed_user_ids`
- Each channel creates a real `ChatRoom` so the full chat/agent/streaming infrastructure is reused
- The outbound reply flow needs a process to listen for ChatRoom broadcasts and relay agent responses back through the gateway's platform API
- Start with Telegram only; WhatsApp/Discord follow the same Gateway+Channel pattern with different Client/Handler modules
