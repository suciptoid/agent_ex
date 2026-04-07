## Chat layout density pass

- Moved the `/chat/:id` scroll shell back to full width and centered each streamed row at `max-w-4xl`, so the scrollbar now sits on the page edge instead of the message column edge.
- Rebuilt the composer footer so the reasoning selector and send/cancel button sit in a normal-flow controls row below the textarea instead of floating over it.
- Removed the chat-room back link, tightened the sidebar to `255px`, reduced the sidebar footer padding to `p-1`, and replaced the sidebar user menu trigger wrapper with a full-width popover container so it no longer renders `w-fit`.
- Reduced the top-right agent selector pill padding and added a stable `#sidebar-new-chat-link` id for chat navigation coverage in tests.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- Browser check on `/chat/:id` confirmed:
  - sidebar width `255px`
  - footer padding `4px`
  - user menu wrapper class `w-full`
  - no back link
  - message scroll shell right edge matching the main pane right edge
  - composer controls remaining below a tall textarea draft
- `mix precommit` still fails only on the unchanged baseline tests:
  - `AppWeb.UserAuthTest`
  - `AppWeb.UserLive.LoginTest`
  - `App.UsersTest`
