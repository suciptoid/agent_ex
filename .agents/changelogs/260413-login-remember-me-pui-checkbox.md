# Login remember me PUI checkbox

- Swapped the login form's remember-me control from a raw checkbox input to `PUI.Input.checkbox`.
- Kept the `login_remember_me` DOM id and `remember_me` field so auth behavior stays unchanged.
- Updated the LiveView test to continue checking for the checkbox by id.

By: gpt-5.4 on Codex
