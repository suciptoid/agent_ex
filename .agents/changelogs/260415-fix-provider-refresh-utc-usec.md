## Fix provider refresh timestamp precision crash

- Root cause: `App.Providers.persist_provider_models/2` used `DateTime.truncate(:second)` for `inserted_at`/`updated_at` values inserted into `provider_models` (`:utc_datetime_usec`), causing Ecto to raise `:utc_datetime_usec expects microsecond precision`.
- Fix: switched to microsecond-precision timestamp generation and reused that timestamp for `models_last_refreshed_at` update.
- File changed: `lib/app/providers.ex`.
- Validation:
  - `mix test test/app/providers_test.exs test/app_web/live/provider_live_test.exs` (pass)
  - `mix precommit` (pass, 215 tests, 0 failures)

By: gpt-5.2 on Codex CLI
