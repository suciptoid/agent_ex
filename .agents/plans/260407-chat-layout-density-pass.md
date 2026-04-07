## Problem

The `/chat/:id` page needs a final density/layout pass:

1. Put the message list scrollbar at the viewport edge instead of the centered content edge.
2. Move the composer controls into a bottom row so the send button does not overlap tall textarea content.
3. Remove the chat-room back button.
4. Make the sidebar `255px` wide.
5. Remove the user-trigger `w-fit` behavior and shrink the sidebar footer padding from `p-3` to `p-1`.
6. Reduce the padding of the top-right agent selector pills.

## Proposed approach

- Keep `#chat-messages` as the full-width scrolling surface and center each direct streamed child to `max-w-4xl`.
- Rebuild the composer actions as a normal-flow footer row below the textarea, preserving the existing reasoning selector behavior.
- Tighten sidebar spacing in `Layouts.dashboard/1` and the reusable badge spacing in `AppWeb.ChatComponents`.
- Re-run targeted chat tests and browser validation, then document any unchanged baseline precommit failures.

## Todos

- `chat-scroll-shell`: move the chat scrollbar to the viewport edge while keeping centered message content.
- `chat-composer-controls-row`: place the reasoning/send controls in a non-floating footer row under the textarea.
- `chat-sidebar-density-pass`: remove the back button and tighten sidebar width/footer/user-trigger spacing.
- `chat-agent-selector-density-pass`: reduce the top-right agent selector padding.
- `chat-layout-pass-validation`: run targeted validation and record any unchanged baseline failures.

## Notes

- The scrollbar issue comes from constraining the scroll container itself; the fix should keep the stream parent full width and constrain its children instead.
- `mix precommit` has existing unrelated failures in `AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, and `App.UsersTest`.
