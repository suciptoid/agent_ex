Updated chat room tool response UX and cross-tab syncing.

Changes made:
- Imported `PUI.Accordion` into shared web helpers and refactored chat tool response sections to use unstyled accordion primitives instead of the custom collapsible hook.
- Simplified tool response labels so chat messages show only the tool name, not argument previews.
- Added chat room PubSub broadcast helpers and published new user messages from `AppWeb.ChatLive.Show` to other subscribers while excluding the sending LiveView process.
- Added LiveView coverage for accordion-based tool rendering, hidden tool args, and immediate user-message propagation to a second open tab before the assistant stream completes.

Validation:
- `mix test test/app_web/live/chat_live_test.exs` passes.
- `mix precommit` still fails on unrelated existing tests outside this chat work: `AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, and `App.UsersTest`.

Follow-up:
- Extended the realtime fix so the primary assistant placeholder, stream chunks, thinking, and tool-result updates are now rendered live in secondary tabs instead of waiting for final completion.
- Added staged streaming test coverage proving a second tab sees the assistant placeholder, partial streamed content, and tool-response UI before the final assistant message completes.
- Re-ran `mix test test/app_web/live/chat_live_test.exs` successfully after the follow-up fix; `mix precommit` still fails only on the same unrelated baseline tests in auth/login/users areas.
- Fixed the chat send button staying in stop/loading mode after terminal assistant updates by explicitly resetting main-stream state on completed/error `:stream_updated` events.
- Hardened the dashboard mobile sidebar hook so LiveView patches no longer reopen it on small screens; the hook now preserves client state across updates and keeps mobile closed by default while only persisting desktop collapse state.
- Added a focused chat regression asserting the send button returns to `aria-label=\"Send message\"` after assistant completion.
- Revalidated with `mix test test/app_web/live/chat_live_test.exs` successfully; `mix precommit` still fails only on the unchanged unrelated baseline tests in `AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, and `App.UsersTest`.
