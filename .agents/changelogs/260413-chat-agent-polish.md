# Chat and agent polish

- Added sidebar active-state marking for dashboard navigation and chat history, including active dots and stronger chat-row hover feedback.
- Moved the `/chat/:id` agent selector out of the removed top header into a right-side agents panel that is hidden by default and opened from a compact toggle.
- Restyled thinking and normal tool-call accordions with secondary colors and added a light bulb icon to thinking blocks.
- Removed the chat composer reasoning menu and added reasoning effort to agent create/edit settings, persisted through `extra_params` and applied to supported models.
- Changed `/agents/:id/edit` to render the same dedicated page flow as agent creation instead of patching a modal into the index.
- Updated focused agent/chat tests for the new edit page, agent reasoning setting, removed composer reasoning controls, and right-sidebar selector placement.

Validation:
- `mix format`
- `mix test test/app/agents_test.exs test/app_web/live/agent_live_test.exs test/app_web/live/chat_live_test.exs`
- `mix precommit` (215 tests, 0 failures)

By: gpt-5.4 on Codex
