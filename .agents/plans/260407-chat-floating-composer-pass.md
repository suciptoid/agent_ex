## Problem

The `/chat/:id` page needs one more layout pass:

1. Restore the standard sidebar user dropdown instead of the custom popover wrapper.
2. Move the send button back inside the same bordered composer box as the textarea.
3. Let the chat history scroll underneath the composer so the input feels like a floating overlay.
4. Add a blurred/translucent effect on the composer while content moves behind it.

## Proposed approach

- Revert `Layouts.dashboard/1` to the stock `menu_button` usage for the sidebar user menu.
- Build the composer as a single floating glass card with an unstyled textarea and an internal footer row for reasoning/send controls.
- Keep the message list full-height with extra bottom padding so it can scroll behind the composer without obscuring the latest message.
- Re-run targeted chat tests, a browser check, and the repo precommit alias, documenting only the unchanged baseline failures.

## Todos

- `chat-user-menu-restore`: revert the sidebar user menu to the original stock dropdown component.
- `chat-floating-composer-shell`: rebuild the composer as one bordered floating card with the send button inside it.
- `chat-scroll-under-composer`: let the message list scroll behind the floating composer and add the blurred glass effect.
- `chat-floating-composer-validation`: run targeted validation and record any unchanged baseline failures.

## Notes

- The target UI is a single rounded composer card with glassmorphism, not a separate textarea plus separate controls row.
- `mix precommit` still has unrelated baseline failures in `AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, and `App.UsersTest`.
