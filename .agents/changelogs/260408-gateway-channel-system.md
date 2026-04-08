# 260408 — Gateway & Channel System Changelog

## Changes

### New Files

- `priv/repo/migrations/20260408130831_create_gateways.exs` — Migration for `gateways` and `gateway_channels` tables
- `lib/app/gateways/gateway.ex` — `App.Gateways.Gateway` schema with Ecto.Enum type/status, encrypted token, embedded Config
- `lib/app/gateways/gateway_config.ex` — `App.Gateways.Gateway.Config` embedded schema (agent_id, allow_all_users, allowed_user_ids, welcome_message, allowed_updates)
- `lib/app/gateways/channel.ex` — `App.Gateways.Channel` schema mapping external chats to internal ChatRooms
- `lib/app/gateways.ex` — `App.Gateways` context with gateway CRUD, channel find_or_create, access control
- `lib/app/gateways/telegram/client.ex` — `App.Gateways.Telegram.Client` Req-based Telegram Bot API client
- `lib/app/gateways/telegram/handler.ex` — `App.Gateways.Telegram.Handler` update dispatcher, channel auto-creation, agent relay
- `lib/app_web/controllers/gateway_webhook_controller.ex` — Webhook endpoint for `/gateway/webhook/:gateway_id`
- `lib/app_web/live/gateway_live/index.ex` — Gateway list/management LiveView
- `lib/app_web/live/gateway_live/index.html.heex` — Gateway index template
- `lib/app_web/live/gateway_live/form_component.ex` — Gateway create/edit form dialog

### Modified Files

- `lib/app/organizations/organization.ex` — Added `has_many :gateways` association
- `lib/app_web/router.ex` — Added webhook route (`POST /gateway/webhook/:gateway_id` under `:api`), gateway LiveView routes under `:require_active_organization`

## Architecture Notes

- Gateway webhook route is under `:api` pipeline (no CSRF/session needed)
- Gateway management routes are in `:require_active_organization` live_session (requires auth + active org)
- Token encryption uses existing `App.Encrypted.Binary` (Cloak) — same pattern as Provider api_key
- Webhook secret auto-generated per gateway via `:crypto.strong_rand_bytes/1`
- Telegram handler runs in a Task to return 200 quickly
- Agent response relay subscribes to ChatRoom PubSub broadcasts and forwards completed messages back to Telegram

By: Claude Opus 4.6 on GitHub Copilot

## Follow-up Fixes

- Fixed `lib/app_web/live/gateway_live/form_component.ex` so all PUI selects now use `{value, label}` tuples. This corrects gateway type submission (`telegram`/`whatsapp_api`), status values, and agent option labels.
- Switched the `allow_all_users` control from a text-style checkbox input to the proper PUI checkbox pattern with an explicit hidden `false` field, so the boolean posts reliably and renders with the expected checkbox UI.
- Added `test/app_web/live/gateway_live_test.exs` to cover the `/gateways/new` form, verify the rendered option values/labels, and confirm a Telegram gateway can be created successfully with nested config values.

By: gpt-5.4 on GitHub Copilot

## Sidebar + Webhook Sync Follow-up

- Added a `Gateways` link under the sidebar `Agents` group so gateway management is reachable from the dashboard navigation.
- Added an inline enable switch to `lib/app_web/live/gateway_live/index.html.heex` and `index.ex`; toggling a gateway now updates its `status` from the list view and re-streams the updated record.
- Added `lib/app/gateways/telegram/webhook.ex` to build the Telegram webhook URL from `AppWeb.Endpoint.url()`, call `setWebhook`, include `secret_token` and `allowed_updates`, and mark the gateway as `:error` if webhook registration fails.
- Updated `lib/app_web/live/gateway_live/form_component.ex` so newly created or edited active Telegram gateways attempt webhook registration immediately after save.
- Updated `lib/app/gateways/telegram/client.ex` to support Req test options, and expanded `test/app_web/live/gateway_live_test.exs` to cover sidebar navigation, inline activation, and webhook registration on create/toggle.

By: gpt-5.4 on GitHub Copilot
