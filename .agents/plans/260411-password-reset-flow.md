# Password reset flow + login remember checkbox

## Goal

Restore password reset via email token flow and simplify login form to one submit button with a remember-me checkbox.

## Scope

1. Read previous auth changelog context and align reset flow with current password-based auth.
2. Reintroduce reset password token support in Users context, token verification, and notifier email delivery.
3. Add LiveViews and routes for forgot-password and reset-password token pages in the existing public `live_session :current_user` scope.
4. Update login page UX to keep one login button and a checkbox for remember login.
5. Add/update tests for context + LiveView reset flow and login form behavior.
6. Run `mix precommit`, then write changelog, commit, and open PR.

## Router placement

- Place forgot/reset password LiveView routes in the existing public `scope "/", AppWeb` with `pipe_through [:browser]` and inside existing `live_session :current_user`.

Why:
- These pages must be available pre-authentication while still receiving `@current_scope` assignment through `:mount_current_scope`.
