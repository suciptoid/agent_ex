# 260408 — Gateway chat preload

## Changes

- Added `App.Chat.preload_chat_room/1` so gateway-driven chat flows can reuse the full chat room preload, including `chat_room_agents.agent.provider`.
- Updated `App.Gateways.Telegram.Handler` to preload the gateway channel chat room before streaming, start the relay only after the PubSub subscription is ready, and send Telegram replies from streamed completion payloads.
- Updated `App.Chat.StreamWorker` to emit `:stream_complete` and `:stream_error` events for the root assistant message so gateway relays can react to finished streams even when the stream worker rotates message ids internally.
- Added `test/support/stubs/preloaded_provider_runner_stub.ex` plus `test/app/gateways/telegram/handler_test.exs` to lock in the regression: gateway chats now reach the runner with a preloaded provider and relay the assistant reply back through Telegram.

By: gpt-5.4 on GitHub Copilot
