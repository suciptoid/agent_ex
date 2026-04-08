# Changelog 2026-04-08

## Dashboard and agents refactor
- Replaced the placeholder `/dashboard` content with real workspace data: provider, agent, tool, and conversation counts plus recent conversations and recently added agents.
- Added lightweight count/recent query helpers in the Providers, Tools, Agents, and Chat contexts so the dashboard can stay informative without loading full chat transcripts.
- Redesigned `/agents` into a single-column list that shows each agent's name, provider, model name, and tool count badge, while keeping edit and delete icon actions.
- Moved `/agents/new` into a dedicated authenticated LiveView page and updated the shared agent form component so it can render in full-page mode for create and dialog mode for edit.
- Refreshed the dashboard and agent LiveView tests to cover the new dashboard content, the single-column agent list, and the dedicated new-agent flow.
- `mix precommit` still reports unrelated existing failures in auth/users tests; the affected dashboard, agent, and chat test slices pass.
