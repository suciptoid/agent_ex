## Goal
Prevent authenticated users from viewing the login LiveView.

## Plan
1. Inspect the current login LiveView mount and router placement.
2. Add an authenticated-user redirect in `AppWeb.UserLive.Login`.
3. Add a regression test that asserts logged-in users are redirected away from `/users/log-in`.
4. Run targeted tests, then `mix precommit`, and record the outcome in a changelog.
