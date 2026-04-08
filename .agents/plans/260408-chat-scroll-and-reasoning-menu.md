# Chat scroll and reasoning menu fixes

## Problem

The `/chat/:id` screen still has two UX regressions:

1. Typing quickly can make the message history jump because the sticky-scroll hook reacts to general LiveView updates, not only message-list changes.
2. The reasoning selector popup is clipped by the floating composer shell even though the popover tries to switch to `position: fixed`.

## Proposed approach

- Reproduce both issues in the browser to confirm whether the jump comes from composer/layout updates versus stream updates, and whether the popup remains inline inside a clipping ancestor.
- Tighten the `.ChatMessages` hook so sticky scroll only runs for explicit bottom-scroll requests or actual message-list growth, while still preserving manual scroll position and accordion anchoring.
- Patch the chat composer and/or PUI popover so dropdown content can escape clipping ancestors reliably, then save an upstreamable patch artifact for the PUI change.
- Re-run the existing project checks after the fix and document any remaining baseline failures separately from this work.

## Todos

- `chat-scroll-stability`: keep the history stable while the composer reflows during fast typing.
- `reasoning-menu-clipping`: stop the reasoning selector popup from being clipped inside the floating composer.
- `validate-chat-ui-fix`: run project validation and record the final change summary.

## Notes

- Recent chat work already introduced bottom-sticky scrolling, accordion anchoring, and the floating composer; the new changes should preserve those behaviors.
- PUI dropdowns currently render inline and use the popover hook with `data-strategy="auto"`, so a library-level escape hatch may be needed if CSS clipping still applies with `position: fixed`.

## Status

- Implemented.
- Browser verification confirmed the reasoning popup is no longer clipped and composer typing no longer triggers chat-history jump scroll.
- `mix test test/app_web/live/chat_live_test.exs` passes.
- `mix precommit` still reports the same unrelated baseline failures in `AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, and `App.UsersTest`.

## Follow-up regression

- The composer offset CSS variable was flickering between the server fallback (`12rem`) and the measured value during every `validate` patch, because the hook wrote the variable onto the same LiveView-patched node that also rendered the fallback inline style.
- Fix approach:
  - keep the layout style static as `var(--chat-room-layout-composer-offset, 12rem)`
  - move the measured pixel value to `document.documentElement`
  - sync via `ResizeObserver` and dedupe repeated writes so typing only recomputes when the composer height actually changes
