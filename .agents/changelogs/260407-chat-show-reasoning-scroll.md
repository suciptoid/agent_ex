## Changes

- Added model-aware reasoning controls to `/chat/:id`:
  - detect reasoning support from ReqLLM model metadata
  - show a floating bottom-left PUI dropdown only for reasoning-capable active agents
  - support `Auto`, `Disabled`, `Minimal`, `Low`, `Medium`, `High`, and `X-High`
  - thread the selected effort into the chat streaming pipeline

- Tightened the composer layout:
  - wrapped the composer in a centered max-width container
  - added horizontal breathing room around the form
  - reserved left-side textarea padding so the floating reasoning control does not overlap typed content

- Reworked chat scrolling behavior:
  - switched message rendering to normal append order instead of reversed flex layout
  - changed sticky-scroll logic to track distance from the bottom
  - keep auto-scroll active only while the user is near the latest message
  - keep the floating “Scroll to bottom” button visible while the user is reading older messages
  - resume sticky auto-scroll when the user returns to the bottom or uses the button

- Fixed accordion jump-scroll behavior:
  - removed the unused custom collapsible hook
  - anchor accordion toggles to the clicked summary position so expanding/collapsing thinking/tool blocks no longer jumps the view to the top

- Added LiveView coverage for:
  - reasoning controls rendering for supported models
  - reasoning controls being hidden for unsupported models
  - forwarding the selected reasoning effort into the chat streaming request

## Validation

- `mix test test/app_web/live/chat_live_test.exs` passes
- Browser spot-check on the seeded `/chat/:id` page confirmed:
  - reasoning control placement and composer spacing
  - scroll-to-bottom button visibility and recovery to the latest message
  - accordion toggles no longer jumping to the top
- `mix precommit` still fails on pre-existing unrelated tests:
  - `AppWeb.UserAuthTest`
  - `AppWeb.UserLive.LoginTest`
  - `App.UsersTest`
