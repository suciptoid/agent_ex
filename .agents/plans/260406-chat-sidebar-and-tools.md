# Chat Sidebar, Title Tool & Agent Management

## Problem
- Chat history not visible in sidebar
- No auto-title generation for new chats
- Agent management in chat is limited (not clickable, can't add/remove)
- Sidebar text too grey

## Approach

### Phase 1: Data Layer
- Make ChatRoom.title optional (new chats start without title)
- Add `Chat.list_chat_rooms_for_sidebar/1` (lightweight query)
- Add `Chat.update_chat_room_title/2`

### Phase 2: Internal Tool `update_chatroom_title`
- Build tool in Orchestrator that updates chatroom title
- Inject when chatroom has no title (first message scenario)
- Add system instruction to call the tool
- Hide tool calls from UI (filter in `tool_responses/1`)

### Phase 3: New Chat Flow (ChatLive.Index rewrite)
- `/chat` = blank chatroom (like ChatGPT/Claude)
- Default to last created agent, allow changing
- On first message: create chatroom → start stream → navigate to `/chat/:id`
- Remove `/chat/new` route

### Phase 4: Sidebar Chat History
- Add `on_mount` hook to load sidebar chat rooms for all authenticated LVs
- Add "Chats" section to dashboard layout below nav links
- Pass `sidebar_chat_rooms` to `Layouts.dashboard` in all templates
- Update sidebar when title changes

### Phase 5: Agent Management on Chat Detail
- Make agent badges clickable (set active, remove)
- Add "+" button to add agents to room
- Popover/dropdown for agent actions

### Phase 6: UI Polish
- Darker sidebar menu text color

## Follow-up Adjustments
- Replace always-visible agent chips with a compact select-driven picker in both `/chat` and `/chat/:id`
- Keep add/remove agent actions inside the picker dropdown instead of inline in the header
- Seed chat titles deterministically from the first user prompt so titles still update when the model does not call the internal tool

## Latest UI Pass
- Replace the select-based picker with a dropdown badge selector shared by both chat screens
- Move agent selection for `/chat` into the centered empty-state body under the welcome copy
- Hide the header-level selector in `/chat/:id` until the room has at least one message
- Increase chat composer padding and make the sidebar chat header sticky while removing chat row icons
- Refresh LiveView coverage for the new selector structure
