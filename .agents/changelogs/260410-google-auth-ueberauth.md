## Google auth with Ueberauth

- Added `ueberauth` and `ueberauth_google` in [mix.exs](/Users/sucipto/Developer/agent_ex/mix.exs), configured Google OAuth plus Tesla warning suppression in [config.exs](/Users/sucipto/Developer/agent_ex/config/config.exs), required Google client credentials in production in [runtime.exs](/Users/sucipto/Developer/agent_ex/config/runtime.exs), and set test credentials in [test.exs](/Users/sucipto/Developer/agent_ex/config/test.exs).
- Added a nullable unique `google_id` column for users in [20260410102920_add_google_id_to_users.exs](/Users/sucipto/Developer/agent_ex/priv/repo/migrations/20260410102920_add_google_id_to_users.exs).
- Extended the users domain in [users.ex](/Users/sucipto/Developer/agent_ex/lib/app/users.ex) and [user.ex](/Users/sucipto/Developer/agent_ex/lib/app/users/user.ex) with password-based registration changesets, Google account lookup/link/create logic, and Google OAuth configuration checks.
- Added [user_oauth_controller.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/controllers/user_oauth_controller.ex) for `ueberauth` request/callback handling and simplified [user_session_controller.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/controllers/user_session_controller.ex) to password login only.
- Kept Google OAuth controller routes in the public browser scope and kept the registration/login LiveViews inside the existing `live_session :current_user` block in [router.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/router.ex). This preserves `current_scope` loading for public auth pages while keeping OAuth callbacks session-aware before authentication.
- Reworked [login.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/user_live/login.ex) and [registration.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/user_live/registration.ex) to remove visible magic-link auth, add Google buttons, and support password signup. Removed the old token confirmation LiveView in [confirmation.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/user_live/confirmation.ex).
- Updated fixtures and auth coverage in [users_fixtures.ex](/Users/sucipto/Developer/agent_ex/test/support/fixtures/users_fixtures.ex), [users_test.exs](/Users/sucipto/Developer/agent_ex/test/app/users_test.exs), [user_session_controller_test.exs](/Users/sucipto/Developer/agent_ex/test/app_web/controllers/user_session_controller_test.exs), [user_oauth_controller_test.exs](/Users/sucipto/Developer/agent_ex/test/app_web/controllers/user_oauth_controller_test.exs), [login_test.exs](/Users/sucipto/Developer/agent_ex/test/app_web/live/user_live/login_test.exs), and [registration_test.exs](/Users/sucipto/Developer/agent_ex/test/app_web/live/user_live/registration_test.exs). Removed the obsolete confirmation LiveView test in [confirmation_test.exs](/Users/sucipto/Developer/agent_ex/test/app_web/live/user_live/confirmation_test.exs).

## Validation

- `mix test test/app/users_test.exs test/app_web/controllers/user_session_controller_test.exs test/app_web/controllers/user_oauth_controller_test.exs test/app_web/live/user_live/login_test.exs test/app_web/live/user_live/registration_test.exs`
- `mix precommit`

By: gpt-5 on Codex
