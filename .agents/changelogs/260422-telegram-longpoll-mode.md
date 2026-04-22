# 260422 — Telegram Longpoll Mode

- Added Telegram gateway `update_mode` config with `webhook` default and `longpoll` support, and exposed it in the gateway form so Telegram gateways can explicitly choose their delivery mode.
- Extended Telegram transport sync in `lib/app/gateways/telegram/webhook.ex` so active webhook gateways register `setWebhook`, active long-poll gateways clear webhook state with `deleteWebhook`, and inactive Telegram gateways stop both delivery paths cleanly.
- Added supervised Telegram long-poll runtime in `lib/app/gateways/telegram/runtime.ex` and `lib/app/gateways/telegram/poller.ex`, backed by a registry and dynamic supervisor in `lib/app/application.ex`. Active long-poll gateways can now consume `getUpdates` through a managed GenServer worker.
- Extended `lib/app/gateways/telegram/client.ex` with `get_updates/2` and added `test/app/gateways/telegram/poller_test.exs` to verify the `getUpdates` flow creates channels and advances offsets correctly.
- Fixed a bug in the in-progress pending-channel approval work: `App.Gateways.approve_channel/3` now rejects blank `user_id` values, and the chat-room approval banner now submits through an explicit Approve button instead of auto-approving on select change.
- Updated gateway and handler tests to cover Telegram update-mode UI, long-poll save behavior, and the current relay message ordering.
- Verification:
  - `mix test test/app_web/live/gateway_live_test.exs test/app/gateways/telegram/poller_test.exs test/app/gateways/telegram/handler_test.exs`
  - `mix test test/app_web/live/chat_live_test.exs`
  - `mix precommit`

By: gpt-5.4 on OpenCode
