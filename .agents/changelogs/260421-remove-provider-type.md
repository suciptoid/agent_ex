# Remove `provider_type`

- Removed `provider_type` from the provider schema and the provider form.
- Refactored Alloy/provider classification to derive from `provider` only.
- Updated the existing alloy migration to stop adding/backfilling `provider_type`.
- Adjusted provider tests to reflect the single-field model.

Validation:
- `mix test test/app/providers_test.exs test/app_web/live/provider_live_test.exs`
- `mix precommit` ran, but the suite ended with one unrelated failing `AppWeb.ChatLiveTest` case.

By: gpt-5.4 on Github Copilot
