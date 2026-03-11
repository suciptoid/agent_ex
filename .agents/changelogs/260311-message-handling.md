Implemented the message-handling plan from `.agents/plans/260311-message-handling.md`.

Changes
- Switched chat message status handling to `Ecto.Enum` values `:pending`, `:streaming`, `:error`, and `:completed`.
- Added a migration to normalize legacy `requesting` statuses to `pending`.
- Updated the LLM runner to use the streaming API consistently, accumulate thinking/tool-response metadata, and surface tool results through callbacks.
- Persisted streaming metadata (`thinking`, `tool_responses`, `usage`, `finish_reason`, `provider_meta`) onto assistant messages.
- Updated orchestrator flows, including delegated-agent streaming, to use the new result shape and to persist explicit error content on failures.
- Added regenerate/retry support for the latest assistant response, reusing the same message record.
- Updated the chat UI to show hover-only estimated cost, collapsible thinking/tool-response sections, and improved latest-message defaults.
- Updated the chat room list to a single-column layout with a compact icon-only delete action.
- Updated the agent list to remove prompt preview and use icon-only edit/delete actions.
- Refreshed stubs and tests, including a streaming-metadata stub plus LiveView coverage for regenerate and metadata rendering.

Validation
- `mix compile` ✅
- `mix test test/app/chat_test.exs test/app_web/live/chat_live_test.exs test/app_web/live/agent_live_test.exs` ✅
- `mix precommit` ⚠️ blocked by unrelated pre-existing auth/user suite failures (for example `test/app_web/controllers/user_session_controller_test.exs`, `test/app_web/live/user_live/login_test.exs`, `test/app_web/live/user_live/settings_test.exs`, `test/app_web/live/user_live/registration_test.exs`, `test/app_web/user_auth_test.exs`).
- Re-ran `mix compile` and targeted chat/agent tests after the final formatting/validation pass; they still passed.
