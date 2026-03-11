# Chat Autoscroll Feature

## Changes
- Added colocated hook `.ChatMessages` to `show.html.heex`
- Auto-scrolls to bottom when new messages arrive (only if user is within 10% of bottom)
- Shows scroll-to-bottom button when user scrolls up past threshold
- Button positioned outside stream container to persist across updates
- Smooth scrolling animation using `scrollTo({ behavior: "smooth" })`

## Files Modified
- `lib/app_web/live/chat_live/show.html.heex`
  - Added `phx-hook=".ChatMessages"` to message list container
  - Added scroll-to-bottom button with absolute positioning
  - Added colocated JS hook for scroll tracking

## Technical Details
- Threshold: 10% of scrollHeight (not fixed pixels)
- Uses `updated()` callback to detect new messages via stream updates
- Button visibility toggles based on scroll position
- Smooth scroll animation for better UX