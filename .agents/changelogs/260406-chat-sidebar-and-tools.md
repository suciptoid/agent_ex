# Chat Sidebar & Tools Changelog

## Summary

Implemented ChatGPT/Claude-style chat UX: blank chatroom on `/chat`, auto-generated titles, sidebar chat history, interactive agent management, and darker sidebar text.

## Changes

### Data Layer
- `chat_room.ex`: Made title optional (removed from `validate_required`), relaxed agent_ids validation
- `chat.ex`: Added `list_chat_rooms_for_sidebar/1`, `update_chat_room_title/2`; modified `create_chat_room/2` to handle empty agent_ids

### Internal Tool: `update_chatroom_title`
- `orchestrator.ex`: Added `maybe_inject_title_tool/3`, `build_update_title_tool/1`, `notify_title_updated/2` — injects auto-title tool when chatroom has no title
- `stream_worker.ex`: Added `:on_title_updated` callback handler that persists title and broadcasts
- `show.ex`: Filters `update_chatroom_title` from tool_responses display; handles `:chatroom_title_updated` broadcast

### New Chat Flow (ChatLive.Index)
- `index.ex`: Complete rewrite — blank chatroom with agent selector, sends first message → creates room + stream → navigates to `/chat/:id`
- `index.html.heex`: Complete rewrite — centered welcome UI, agent badge selector, message input with `.ChatInput` hook
- `router.ex`: Removed `/chat/new` route

### Sidebar Chat History
- `user_auth.ex`: Added `sidebar_chat_rooms` loading in `on_mount(:require_authenticated)`
- `layouts.ex`: Redesigned sidebar — "Chats" section with chat room list below nav, "New Chat" (+) button, collapsed state icon
- 8 template files updated to pass `sidebar_chat_rooms` attr to `<Layouts.dashboard>`

### Agent Management (ChatLive.Show)
- `show.ex`: Added `set-active-agent`, `add-agent-to-room`, `remove-agent-from-room` event handlers; loads `available_agents` in mount
- `show.html.heex`: Agent badges now clickable (set active, remove), + "Agent" dropdown to add more agents using `<.menu_button>`

### UI Polish
- `layouts.ex`: Changed nav link text from `text-muted-foreground` to `text-foreground/75` (darker)

### Tests
- `chat_live_test.exs`: Rewrote "lists rooms" and "creates room" tests for new blank chatroom UX; fixed selector ambiguity in "streaming leave" test

## Follow-up Fixes

### Select-based agent picker
- Replaced the always-visible agent chips in both `chat_live/index.html.heex` and `chat_live/show.html.heex` with a compact custom-trigger picker backed by the PUI select hook
- Added `AppWeb.ChatComponents.chat_agent_picker/1` so both chat screens share the same trigger layout and dropdown behavior
- Kept add/remove controls in the picker footer instead of exposing the full agent list in the header

### Title generation reliability
- `orchestrator.ex`: Seed the chat title from the first user prompt as a deterministic fallback before the stream starts, while still injecting the hidden `update_chatroom_title` tool for model-driven refinement
- `chat.ex`: Reject blank title updates and no-op when the title is unchanged
- `stream_worker.ex`: Track the updated chat room title in worker state so repeated tool callbacks do not rebroadcast unchanged titles

### Additional validation
- `chat_live_test.exs`: Added coverage for the select picker presence and auto-generated titles on first-message chat creation

## Latest UI Pass

### Dropdown-based agent selector
- Replaced the shared select-style picker with `AppWeb.ChatComponents.chat_agent_selector/1`, a badge-based selector that shows selected agents inline, lets users click a badge to set the active/default agent, supports removals, and uses `PUI.Dropdown` for `+ Add agent`
- Kept the add-agent affordance visible even when no additional agents are available so the layout stays stable on new chats

### Chat screen layout updates
- `chat_live/index.html.heex`: Moved agent selection below the welcome copy in the new-chat empty state and removed the old top-row picker
- `chat_live/show.html.heex`: Only shows the top-right agent selector after the room has messages, and increased composer padding
- `layouts.ex`: Made the sidebar `Chats` header sticky and removed the chat icon from each chat history row

### Tests
- `chat_live_test.exs`: Updated selector assertions to the dropdown badge UI
