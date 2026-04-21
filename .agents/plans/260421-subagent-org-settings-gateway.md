# Plan: Subagent, Org Settings, and Gateway Updates

## Problem
The app needs a real sub-agent workflow where an agent can spawn work into a child chat room, wait for that child to finish, and receive the result back in the parent room. At the same time, gateway configuration is still single-agent only, organization-level defaults are not configurable or stored as encrypted key/value settings, and the Telegram relay can keep typing after the agent has already finished.

## Approach
1. Extend chat rooms and orchestration so sub-agents run in child chat rooms linked by `parent_id`, with hidden runtime tools for listing/spawn/wait and a report-back path into the parent conversation.
2. Update gateway configuration and room bootstrap so a gateway can carry multiple assigned agents while keeping a separate default/active agent selection.
3. Add organization secrets storage and an organization settings LiveView so `default_agent` becomes configurable instead of implicitly picking the newest agent.
4. Fix the Telegram relay loop so typing shuts down and the terminal reply/error is always delivered when streaming ends.
5. Cover the new behavior with tests, then run `mix precommit`.

## Todos
- Add chat-room parent linkage plus subagent spawn/wait orchestration.
- Add hidden internal tools for `subagent_lists`, `subagent_spawn`, and `subagent_wait`.
- Persist sub-agent completion/error reports back into the parent chat room.
- Extend gateway config/UI/runtime to support multiple assigned agents plus a default agent.
- Add encrypted organization secrets storage and organization settings page for `default_agent`.
- Fix Telegram typing relay completion handling.
- Update automated coverage and run `mix precommit`.

## Notes
- Organization settings should live in the existing authenticated + active-organization route stack, inside the existing `live_session :require_active_organization`, because they are organization-scoped workspace settings that require both authentication and an active organization.
- The new sub-agent tools should stay internal/invisible like other runtime-only tools and must not appear in the assignable tools list.
- The active agent should discover other agents through `subagent_lists`; do not embed the agent roster in the system prompt.
- Gateway-created rooms should use the configured gateway agent roster, with the configured default agent set active when present.
