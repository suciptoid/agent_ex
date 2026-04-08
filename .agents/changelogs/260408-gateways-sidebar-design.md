# Changelog 2026-04-08

## Gateways sidebar design
- Updated the nested `Gateways` sidebar link to use the same icon size, spacing, typography, and hover treatment as the rest of the main navigation while keeping it grouped under `Agents`.
- Added a LiveView regression assertion so the sidebar keeps the expected navigation classes for the `Gateways` entry.
- `mix test test/app_web/live/gateway_live_test.exs` and `mix precommit` pass.

By: gpt-5.4 on GitHub Copilot
