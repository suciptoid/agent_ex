# 2026-04-13 Auth Simple Clean Redesign

## Summary
- Redesigned auth LiveViews for a calm, compact, simple visual style using Tailwind utility classes only (no colocated `app.css` additions).
- Applied a consistent card/layout pattern across login, registration, forgot password, and reset password pages.
- Added dual-theme support (`dark:` utilities) and subtle interaction polish (transitions, hover state refinement).
- Preserved IDs/events used by existing LiveView tests and auth flows.
- Captured design context in `.impeccable.md` per skill requirements.

## Additional Test Alignment
- Updated `test/app_web/controllers/user_session_controller_test.exs` to assert stable post-login behavior (`user_token` + rendered `user.email`) without coupling to route links no longer guaranteed on the home page.

## Validation
- Ran `mix precommit` successfully (0 failures).

By: gpt-5.4 on OpenCode
