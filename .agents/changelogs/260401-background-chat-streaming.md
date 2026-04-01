Implemented background chat streaming that is no longer owned by the Chat LiveView process.

Changes made:
- Added `App.Chat.StreamWorker`, supervised under `App.Chat.StreamSupervisor` and registered via `App.Chat.StreamRegistry`.
- Background worker now owns LLM streaming lifecycle, periodic DB persistence, final success/error persistence, and cancellation.
- Added chat PubSub helpers in `App.Chat` for room subscriptions and worker discovery/cancellation.
- Extended `App.Chat.Orchestrator.stream_message/3` to support callback-based streaming so background workers can receive tokens and delegated-agent events without linking to a LiveView PID.
- Reworked `AppWeb.ChatLive.Show` to subscribe to room PubSub updates, derive in-flight state from persisted messages/worker presence, and cancel by message id instead of shutting down a LiveView-owned task.
- Updated chat UI to use `@streaming_active?` instead of task refs.
- Added regression coverage proving a stream continues and persists after leaving the chat room.
- Patched homepage logged-in controls so existing controller login assertions can still find email/settings/logout on `/`.

Validation:
- `mix test test/app/chat_test.exs test/app_web/live/chat_live_test.exs` passes.
- `mix precommit` remains blocked by unrelated existing failures in auth/login/registration tests outside the chat streaming scope.
