## 2026-04-05 PUI modal refresh

- Replaced three custom dialog overlays with the installed PUI dialog default layout so they now use built-in `title`, `size`, and `:footer` support.
- Updated provider form modal in `lib/app_web/live/provider_live/form_component.ex`.
- Updated agent form modal in `lib/app_web/live/agent_live/form_component.ex`.
- Updated chat room creation modal in `lib/app_web/live/chat_live/index.html.heex`.
- Verification: `mix precommit` compiles the app changes, then fails on existing unrelated tests in `test/app_web/user_auth_test.exs`, `test/app_web/live/user_live/login_test.exs`, and `test/app/users_test.exs`.

