# Gateway chat preload

## Problem

Gateway channel chats are starting agent streams with incomplete chat room associations, so the active agent path can reach the runner without a preloaded provider. The Telegram relay flow also waits for completion events that the stream worker does not emit.

## Approach

1. Reuse a full chat room preload for gateway-driven chat so `chat_room_agents.agent.provider` is loaded before streaming.
2. Make the gateway relay consume completion/error signals from the streaming pipeline in a way that still works for gateway-originated chats.
3. Add a regression test that drives a gateway message through the Telegram handler and asserts the assistant reply is sent.

## Notes

- Keep the fix scoped to the gateway chat path and shared chat preload behavior.
- Prefer extending existing stream events over introducing a second gateway-specific streaming path.
