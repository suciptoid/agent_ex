# Chat Autoscroll & Scroll-to-Bottom Fixes

## Changes

### 1. Verified PUI Dropdown in `chat_agent_selector`
- `chat_components.ex` already uses `<.menu_button>` and `<.menu_item>` from PUI.Dropdown — no changes needed.

### 2. Fixed autoscroll during streaming (`show.html.heex` — `.ChatMessages` hook)
- Added `_programmaticScroll` flag to distinguish user scrolls from programmatic position restores
- Scroll event listener now ignores events triggered by `restoreScrollPosition()`, preventing accidental `isNearLatest = true` when user has intentionally scrolled away
- Extracted `updateButtonVisibility()` for consistent button show/hide
- Added `handleEvent("scroll-to-bottom")` so the server can force scroll to bottom when user sends a message or regenerates

### 3. Repositioned scroll-to-bottom button above chat input
- Moved `#scroll-to-bottom-btn` from absolute bottom-right of messages area to a centered pill above the chat input form
- Styled as a frosted glass pill with icon + "Scroll to bottom" text
- Positioned via `absolute -top-8 left-1/2 -translate-x-1/2` inside a `relative` wrapper around the form

### 4. Added `push_event("scroll-to-bottom")` in `show.ex`
- After `begin_stream` in `handle_event("send")` — forces scroll to bottom when user sends
- After `begin_stream` in `handle_event("regenerate")` — forces scroll to bottom on regenerate

## Files Changed
- `lib/app_web/live/chat_live/show.html.heex` — template + hooks
- `lib/app_web/live/chat_live/show.ex` — push_event calls
