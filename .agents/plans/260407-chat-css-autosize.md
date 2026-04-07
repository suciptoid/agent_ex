## Problem

The `/chat/:id` composer still uses a JS hook to set textarea height. That should be removed in favor of Tailwind's `field-sizing-content`.

## Proposed approach

- Keep the current floating composer shell.
- Delete the height mutation logic from the `ChatInput` hook and leave only the Enter-to-send behavior plus composer offset syncing.
- Use CSS field sizing and the existing `max-h-[50vh]` cap to control the textarea growth.
- Add a regression test that verifies the old height config attribute is gone.

## Todos

- `chat-css-autosize`: remove the JS auto-height path and rely on CSS field sizing.
- `chat-css-autosize-validation`: run targeted validation and record any unchanged baseline failures.

## Notes

- Only the height behavior should change; the composer overlay, blurred shell, and chat scroll-under behavior should remain intact.
- `mix precommit` is still expected to fail on unrelated baseline tests:
  - `AppWeb.UserAuthTest`
  - `AppWeb.UserLive.LoginTest`
  - `App.UsersTest`
