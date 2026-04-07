## Chat shared composer

- Extracted the shared chat composer into `AppWeb.ChatComponents.chat_message_composer/1` so `/chat` and `/chat/:id` now render the same shell, textarea, submit button, and enter-to-send behavior from one source.
- Moved the `ChatInput` colocated hook into that component and made the room-only composer offset sync optional via `layout_target_id`, so the floating `/chat/:id` layout keeps working without duplicating the hook.
- Updated `/chat/:id` to pass its reasoning selector through the component's `:controls` slot, keeping the reasoning menu room-specific while the underlying input box stays shared.
- Tightened chat LiveView coverage so the new-chat page now asserts the same composer shell, autosizing textarea, and controls row that already exist on the room page.

## Validation

- `mix format && mix test test/app_web/live/chat_live_test.exs`
- `mix precommit` still fails only on the unchanged baseline tests:
  - `AppWeb.UserAuthTest`
  - `AppWeb.UserLive.LoginTest`
  - `App.UsersTest`

## Follow-up styling correction

- Restored the shared composer shell to the exact prior `/chat/:id` treatment: `rounded-lg`, `rounded-b-none`, `border-4`, and `border-b-0`, with the extra custom shadow removed.
- Kept the extraction and shared hook logic intact so `/chat` and `/chat/:id` still use the same component while matching the earlier room design.
- Re-ran `mix format && mix test test/app_web/live/chat_live_test.exs && mix precommit`; chat coverage stays green and the same unrelated baseline failures remain in `AppWeb.UserLive.LoginTest`, `AppWeb.UserAuthTest`, and `App.UsersTest`.
