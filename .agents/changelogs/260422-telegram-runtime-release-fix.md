# 260422 — Telegram Runtime Release Fix

- Fixed a production boot regression in `lib/app/gateways/telegram/runtime.ex` by removing the `Mix.env/0` call from release runtime code.
- `App.Gateways.Telegram.Runtime.auto_start?/0` now uses application config only, defaulting to `true`, while tests continue to disable bootstrap via `Application.put_env(:app, App.Gateways.Telegram.Runtime, auto_start?: false)`.
- Verification:
  - `mix test test/app/gateways/telegram/poller_test.exs test/app_web/live/gateway_live_test.exs`

By: gpt-5.4 on OpenCode
