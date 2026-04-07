## Chat CSS autosize

- Removed the textarea height mutation logic from the `/chat/:id` `ChatInput` hook and left the hook responsible only for Enter-to-send behavior plus composer offset syncing.
- Switched the chat textarea to rely on CSS `field-sizing-content` with the existing `max-h-[50vh]` cap instead of the JS auto-height path.
- Added regression coverage to ensure the old `data-max-height-vh` attribute is no longer present.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- Browser check on `/chat/:id` confirmed the textarea grows via CSS, keeps no inline height, and still updates the floating composer offset as content expands.
- `mix precommit` still fails only on the unchanged baseline tests:
  - `AppWeb.UserAuthTest`
  - `AppWeb.UserLive.LoginTest`
  - `App.UsersTest`
