## Chat scroll and reasoning menu fixes

- Stopped the chat history from jumping while composing by adding a message revision signal to `#chat-messages` and only auto-scrolling when the message stream actually changes or the server explicitly asks to jump to bottom.
- Preserved the existing sticky-scroll state during plain composer `validate` updates so growing the textarea no longer forces the floating "Scroll to bottom" pill to appear.
- Fixed the reasoning selector clipping by making the composer shell overflow visible; the popup was already switching to `position: fixed`, but it was still being clipped because it stayed inside the composer shell's `overflow-hidden` paint boundary.
- Confirmed the reasoning menu is fully hit-testable across the whole popup after the composer overflow change.
- No PUI dependency patch was needed for this fix because the immediate clipping cause was local to the chat composer wrapper.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- `mix precommit` still fails on the same unrelated baseline tests:
  - `AppWeb.UserAuthTest`
  - `AppWeb.UserLive.LoginTest`
  - `App.UsersTest`
- Browser verification on `/chat/:id` confirmed:
  - no `#chat-messages.scrollTo(...)` calls during rapid input validation
  - the history stays visually stable while the composer grows
  - the reasoning selector popup is no longer clipped

## Follow-up: composer offset flicker

- Reworked the composer offset plumbing so LiveView patches no longer overwrite the measured value with the server fallback during typing.
- `#chat-room-layout` now keeps a stable fallback reference, while the measured value is written to a root-level CSS custom property (`--chat-room-layout-composer-offset`) that survives `validate` patches.
- Replaced per-input offset syncing with a deduped `ResizeObserver` flow, so the hook updates spacing only when the composer shell actually resizes instead of on every keypress.
