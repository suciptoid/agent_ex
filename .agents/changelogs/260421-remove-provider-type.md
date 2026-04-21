# Remove `provider_type`

- Removed `provider_type` from the provider schema and the provider form.
- Refactored Alloy/provider classification to derive from `provider` only.
- Updated the existing alloy migration to stop adding/backfilling `provider_type`.
- Adjusted provider tests to reflect the single-field model.

Validation:
- `mix test test/app/providers_test.exs test/app_web/live/provider_live_test.exs`
- `mix precommit` ran, but the suite ended with one unrelated failing `AppWeb.ChatLiveTest` case.

By: gpt-5.4 on Github Copilot

## Gemini tool schema fix

- Reworked the `web_fetch` tool schema so Gemini no longer receives `additionalProperties`.
- Kept runtime support for both array-style and map-style headers in `App.Agents.Tools.do_web_fetch/1`.

Validation:
- `mix test test/app/agents/tools_test.exs test/app_web/live/chat_live_test.exs`

By: gpt-5.4 on Github Copilot

## Gemini support

- Added `gemini` as a supported provider value and kept `google` as a backend alias for existing Gemini-backed data.
- Routed Gemini providers to `Alloy.Provider.Gemini`.
- Added Gemini model presets and API-backed model listing support using the Gemini models endpoint.
- Updated provider UI/tests to show Gemini as a selectable option.

Validation:
- `mix test test/app/providers_test.exs test/app_web/live/provider_live_test.exs`
- `mix test test/app_web/live/chat_live_test.exs`
- `mix precommit`

By: gpt-5.4 on Github Copilot
