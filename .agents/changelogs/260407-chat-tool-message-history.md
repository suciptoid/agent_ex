Implemented the chat tool-message history refactor from `.agents/plans/260407-chat-tool-message-history.md`.

Changes
- added `name`, `tool_call_id`, and `parent_message_id` support to `App.Chat.Message` plus a migration for standalone child `role: "tool"` rows
- updated chat queries to load only top-level room messages while preloading child tool messages for rendering and history reconstruction
- added message helpers that read tool responses/tool-call turns from child tool messages first, with fallback support for legacy assistant metadata
- updated the agent runner to expand persisted assistant/tool history back into ReqLLM assistant -> tool -> assistant context and to emit `tool_call_turns` during tool loops
- refactored orchestrator and stream worker persistence so tool results are stored as child tool messages and assistant metadata now records `tool_call_turns`
- updated chat LiveView regeneration to clear persisted tool children before reusing an assistant message
- refreshed chat tests to assert child tool-message persistence instead of assistant `metadata["tool_responses"]`

Validation
- `mix test test/app/chat_test.exs test/app_web/live/chat_live_test.exs` ✅
- `mix precommit` ⚠️ still blocked by the same unrelated baseline failures in the auth/user suites (`AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, `App.UsersTest`)

Actual transcript persistence

Changes
- switched chat reads back to the full ordered room transcript so assistant/tool/final-assistant rows render in their persisted order
- updated the runner and orchestrator to separate assistant tool-call turns from the final assistant answer, storing `metadata["tool_calls"]` on the first assistant turn and the post-tool reasoning/content on the second
- refactored the stream worker to split the active assistant message when tool calls arrive, create standalone `role: "tool"` rows, move the live registry key to the follow-up assistant message, and keep transcript positions stable
- removed LiveView-side streaming DB writes that were reintroducing legacy `tool_responses` metadata and racing against the stream worker's persisted state
- refreshed streaming stubs and chat tests so they assert the real persisted flow and the cross-tab/leave-room cases wait for the background worker lifecycle correctly

Validation
- `mix test test/app/chat_test.exs test/app_web/live/chat_live_test.exs` ✅
- `mix precommit` ⚠️ still blocked only by the same unrelated baseline failures in `AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, and `App.UsersTest`
