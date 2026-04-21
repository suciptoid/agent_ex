Implemented sub-agent orchestration, gateway multi-agent assignment, encrypted organization settings, and the Telegram relay completion fix.

- Added `chat_rooms.parent_id` and `organization_secrets`, plus `App.Organizations.Secret` for Cloak-encrypted org key/value settings.
- Added hidden Alloy tools `subagent_spawn` and `subagent_wait`, child chatroom creation/reporting flow, and parent-room report waiting helpers.
- Added hidden Alloy tool `subagent_lists` so the active agent can inspect the other assigned agents, their instructions, and their tools at runtime.
- Updated multi-agent prompt/tool injection and hid the new runtime-only tools from transcript/tool history surfaces.
- Added organization settings LiveView under the authenticated active-organization scope and made `default_agent` configurable via encrypted org secret storage.
- Changed new chat defaults and gateway defaults to use the organization default agent when present.
- Extended gateway config to support multiple assigned agents while keeping a separate default active agent, with organization ownership validation.
- Fixed Telegram relay completion by monitoring the stream worker instead of waiting on a specific assistant message id.
- Added coverage for sub-agent orchestration, gateway multi-agent bootstrap, and organization settings/default-agent behavior.
- Removed the redundant room-id requirement from the sub-agent tools so they derive the current room from context, while restoring `handover` and `ask_agent` to the multi-agent tool roster.
- Removed the prompt-level agent roster and removed `ask_agent`/`handover` from the multi-agent tool roster so sub-agent discovery now flows through `subagent_lists`.
- Tightened the multi-agent prompt so the active agent must inspect other agents before spawning, optimize the delegated prompt for that agent's tools, and show `subagent_*` tool activity in the chat UI while keeping delegated placeholders visibly in progress.
- Reworked sub-agent reporting so `subagent_wait` returns child results only through tool output, long-running children can call `subagent_report` later, and async reports create a visible parent-room message before restarting the parent agent stream.
- `mix precommit` passes.

By: gpt-5.4 on Github Copilot
