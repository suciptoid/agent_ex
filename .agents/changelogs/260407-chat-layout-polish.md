## Chat layout polish

- Centered the `/chat/:id` message history inside a `max-w-4xl` shell so the timeline and composer align visually.
- Reworked the composer layout so the textarea keeps normal horizontal padding, reserves a bottom control row for reasoning/send controls, and auto-resizes up to `50vh`.
- Updated the dashboard sidebar user trigger to remove the border and truncate the derived display label plus email cleanly for long addresses.
- Fixed the misplaced `@doc` warning in `AppWeb.Layouts` so the follow-up validation runs cleanly.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- Browser check on `/chat/:id` confirmed the centered history width, repaired reasoning/composer layout, capped textarea growth, and borderless truncated sidebar trigger.
- `mix precommit` still fails only on pre-existing baseline tests:
  - `AppWeb.UserLive.LoginTest`
  - `AppWeb.UserAuthTest`
  - `App.UsersTest`
