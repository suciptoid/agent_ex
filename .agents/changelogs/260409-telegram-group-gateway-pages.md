# 260409 — Telegram Group Gateway + Gateway Pages

## Changes

- Kept gateway management inside the existing authenticated active-organization router block:
  - `scope "/", AppWeb`
  - `pipe_through [:browser, :require_authenticated_user, :active_organization_required]`
  - `live_session :require_active_organization`
- Changed `/gateways/new` and `/gateways/:id/edit` to dedicated page LiveViews by routing them to `AppWeb.GatewayLive.Form` instead of reusing the list LiveView with modal patch state.
- Added `lib/app_web/live/gateway_live/form.ex` as the dedicated page LiveView with the existing dashboard layout, back navigation, and full-page form presentation.
- Refactored `lib/app_web/live/gateway_live/form_component.ex` so the gateway form can render in page mode and navigate back to `/gateways` after save while still preserving reusable form logic.
- Simplified `lib/app_web/live/gateway_live/index.ex` and `index.html.heex` so the gateway list no longer manages modal new/edit state and now uses full-page navigation links.
- Updated Telegram channel creation/sync logic in `lib/app/gateways.ex` so existing channels can refresh stored identity and metadata, and linked chat room titles stay aligned with the gateway channel label.
- Updated `lib/app/gateways/telegram/handler.ex` so Telegram group chats use a stable group title for the channel while each inbound user message keeps the actual sender name for chat context.
- Added Telegram chat metadata persistence (`chat_type`, `chat_title`, `chat_username`) for gateway channels to support group chat handling and future routing context.
- Corrected embedded gateway config value reads so explicit false values such as `allow_all_users: false` are preserved instead of falling back to defaults.
- Expanded `test/app_web/live/gateway_live_test.exs` to cover dedicated new/edit gateway pages and redirect-based saves.
- Expanded `test/app/gateways/telegram/handler_test.exs` to cover Telegram group message handling, stable group channel naming, and per-message sender names.

## Validation

- `mix test test/app_web/live/gateway_live_test.exs test/app/gateways/telegram/handler_test.exs`
- `mix precommit`

By: gpt-5.4 on GitHub Copilot

## Gateway Chat Broadcast Fix

- Traced a follow-up report where Telegram group messages appeared to create no activity in the open web chat room.
- Fixed `lib/app/gateways/telegram/handler.ex` so gateway-originated user messages now broadcast `{:user_message_created, message}` after persistence, matching the normal in-app chat flow.
- Fixed the same handler to broadcast `{:agent_message_created, assistant_message}` when a gateway-triggered assistant placeholder is created, so open LiveViews refresh immediately instead of waiting for later stream updates.
- Added `test/app/gateways/telegram/handler_test.exs` coverage proving gateway messages publish both PubSub events for chat subscribers.

## Validation

- `mix test test/app/gateways/telegram/handler_test.exs`
- `mix precommit`

By: gpt-5.4 on GitHub Copilot

## Follow-up Troubleshooting Note

- Investigated a report where `/start` worked in a Telegram group but later plain messages never reached the chat room and produced no bot reply.
- Confirmed the app-side Telegram handler already supports group `message` updates; the observed pattern matches Telegram privacy-mode delivery rules, where commands can arrive but ordinary group text may not be forwarded.
- Added a visible setup note to `lib/app_web/live/gateway_live/form_component.ex` telling users to disable BotFather privacy mode or make the bot an admin for full group-message delivery.
- Extended `test/app_web/live/gateway_live_test.exs` to assert that the setup note is rendered on the dedicated gateway form page.

## Validation

- `mix test test/app_web/live/gateway_live_test.exs`
- `mix precommit`

By: gpt-5.4 on GitHub Copilot
