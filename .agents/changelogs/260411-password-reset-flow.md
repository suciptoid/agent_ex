## Password reset flow + login remember checkbox

- Restored password-reset token support in `App.Users` by adding delivery, token lookup, and password reset operations that expire existing tokens on success.
- Extended `App.Users.UserToken` with reset-password token verification (`reset_password` context, one-day validity) and added reset-password email copy in `App.Users.UserNotifier`.
- Added new public auth LiveViews: `UserLive.ForgotPassword` at `/users/reset-password` and `UserLive.ResetPassword` at `/users/reset-password/:token` in the existing `live_session :current_user` scope.
- Updated login UI to use a single login button plus a remember-me checkbox and added a "Forgot password?" link to the reset flow.
- Added/updated tests covering reset-password context logic and LiveView behavior for forgot/reset password pages and login form elements.

## Validation

- Attempted to run formatting and test/precommit flow, but the environment could not install Hex dependencies due SSL tunnel restrictions (HTTP 403), so Mix tasks could not be executed.

By: gpt-5.3-codex on Codex
