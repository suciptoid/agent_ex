Optimized the dashboard sidebar for small viewports.

Changes made:
- Moved the mobile sidebar out of the flex flow so hidden state no longer reserves blank inline space.
- Kept desktop collapse behavior inline with persisted compact width.
- Added a mobile-only floating sidebar launcher so the auto-collapsed sidebar stays accessible on small screens.
- Ensured the main content shell explicitly spans full width while the mobile launcher is present.
- Added a focused `DashboardLiveTest` regression covering the dashboard shell and mobile sidebar trigger.

Validation:
- `mix compile` passes.
- `mix test test/app_web/live/dashboard_live_test.exs` passes.
- `mix precommit` still fails only on pre-existing unrelated baseline tests in `AppWeb.UserLive.LoginTest`, `AppWeb.UserAuthTest`, and `App.UsersTest`.
