## Problem

The `/chat/:id` page needs four related UX fixes:

1. Add horizontal breathing room to the composer so it does not feel edge-to-edge.
2. Expose ReqLLM reasoning controls in the composer when the active agent model supports reasoning, including an explicit disabled mode if the library supports it.
3. Fix the thinking/tool accordions so collapsing them does not yank the scroll position.
4. Make auto-scroll respect manual upward scrolling, show a floating jump-to-bottom button, and resume sticky scrolling once the user returns to the bottom.

## Proposed approach

- Inspect the active agent model with ReqLLM model metadata/capabilities and derive the available reasoning state in `ChatLive.Show`.
- Add a floating PUI dropdown on the bottom-left of the composer, thread the selected reasoning effort into the streaming pipeline, and preserve existing behavior with an explicit default/disabled option.
- Simplify the message list scroll mechanics around streaming updates, manual scrolling, and accordion toggles so the viewport stays stable unless the user is intentionally pinned to the latest message.
- Cover the new UI and state wiring with LiveView tests, then run the project precommit alias. Current baseline already has unrelated failures outside this work.

## Todos

- `chat-composer-spacing`: tighten the `/chat/:id` composer layout and add left-side space for controls.
- `chat-reasoning-controls`: surface model-aware reasoning options in the composer and thread the selected effort into ReqLLM streaming calls.
- `chat-scroll-behavior`: fix accordion jump-scroll and make sticky auto-scroll opt out while the user is reading older messages.
- `chat-tests-and-validation`: update/add LiveView coverage and run targeted tests plus `mix precommit`, noting unrelated baseline failures if they remain.

## Notes

- ReqLLM supports canonical `reasoning_effort` values including `:none`, `:minimal`, `:low`, `:medium`, `:high`, `:xhigh`, and `:default`.
- Reasoning capability can be detected from model metadata (`ReqLLM.ModelHelpers.reasoning_enabled?/1` / `model.capabilities.reasoning`).
- Baseline `mix precommit` currently fails in unrelated existing tests:
  - `AppWeb.UserLive.LoginTest`
  - `AppWeb.UserAuthTest`
  - `App.UsersTest`

## Status

- Implemented.
- Chat LiveView test file passes.
- Full `mix precommit` still reports the same unrelated baseline failures listed above.
