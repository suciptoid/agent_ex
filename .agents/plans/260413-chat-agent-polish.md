# Chat and agent polish

## Context

- Skill flow: `$polish`, with `impeccable` preparation from `.impeccable.md`.
- Design context: calm, compact, simple, reliable product UI with dual-theme support.
- Quality bar: production polish pass.
- Relevant authenticated routes live in `lib/app_web/router.ex` inside the existing `:require_active_organization` LiveView session under the `[:browser, :require_authenticated_user, :active_organization_required]` pipeline. This is correct because chat and agent management require a logged-in user, active organization, and `@current_scope`.

## Tasks

- [x] Add active state indicators to dashboard sidebar menu items and chat history.
- [x] Add a more distinct hover background for chat history rows.
- [x] Restyle chat thinking and tool-call blocks to use the secondary/accent family and add a bulb icon to thinking blocks.
- [x] Remove the chatroom top header and move the agent selector into a hidden-by-default right sidebar with a toggle.
- [x] Remove the reasoning selector from the chat composer and move reasoning effort into agent create/edit settings.
- [x] Change agent edit from modal patch flow to a full page matching agent creation.
- [x] Delegate focused test-surface inspection to executor.
- [x] Update focused tests and run validation, then run `mix precommit`.

## Validation

- `mix format`
- `mix test test/app/agents_test.exs test/app_web/live/agent_live_test.exs test/app_web/live/chat_live_test.exs`
- `mix precommit` (215 tests, 0 failures)

## Notes

- Avoid new component systems. Continue using PUI components and Tailwind utility composition.
- Keep route changes inside the existing authenticated active-organization scope.
