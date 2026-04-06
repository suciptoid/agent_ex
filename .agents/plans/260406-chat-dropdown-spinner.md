# Chat dropdown and sidebar loading plan

## Problem
- Confirm the chat agent selector already matches the requested PUI dropdown badge UX.
- Add a loading spinner on the right side of each sidebar chat title while a room has a pending or streaming assistant response.

## Approach
1. Verify the current dropdown badge selector and keep the implementation if it already satisfies the request.
2. Extend `App.Chat.list_chat_rooms_for_sidebar/1` with a loading flag based on pending or streaming assistant messages.
3. Update `Layouts.dashboard/1` so each chat row can show a right-aligned spinner while keeping the sticky `Chats` header intact.
4. Add focused coverage for the loading state and run the chat-focused validation commands.

## Notes
- The shared selector lives in `AppWeb.ChatComponents.chat_agent_selector/1`.
- The sidebar row markup is in `lib/app_web/components/layouts.ex`.
