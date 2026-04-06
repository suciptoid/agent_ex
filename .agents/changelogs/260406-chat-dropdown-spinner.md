# Chat dropdown and sidebar loading changelog

## Summary
- Verified the requested PUI dropdown badge selector was already in place for chat agent selection.
- Added a sidebar loading spinner that appears on the right side of a chat title while the room has a pending or streaming assistant reply.

## Changes

### Agent selector verification
- Confirmed `AppWeb.ChatComponents.chat_agent_selector/1` already uses `PUI.Dropdown` via `<.menu_button>` and renders the requested badge-style `[agent] [+ add agent]` interaction on the chat screens.

### Sidebar loading state
- `lib/app/chat.ex`: Extended `list_chat_rooms_for_sidebar/1` to include a `loading` flag derived from assistant messages with `:pending` or `:streaming` status.
- `lib/app_web/components/layouts.ex`: Updated sidebar chat rows to keep the title truncated while rendering a right-aligned spinning `hero-arrow-path` icon when `chat.loading` is true.
- `lib/app_web/live/chat_live/show.ex`: Refreshes `sidebar_chat_rooms` when chat room message/title updates arrive so the spinner state stays accurate during chat activity.

### Tests
- `test/app/chat_test.exs`: Added coverage for the sidebar loading flag returned by `list_chat_rooms_for_sidebar/1`.
- `test/app_web/live/chat_live_test.exs`: Added LiveView coverage for the rendered sidebar spinner on pending assistant replies.

## Validation
- `mix test test/app/chat_test.exs test/app_web/live/chat_live_test.exs`
- `mix precommit` still stops on the same unrelated baseline failures in `AppWeb.UserLive.LoginTest`, `AppWeb.UserAuthTest`, and `App.UsersTest`
