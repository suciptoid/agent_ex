# Plan: Tool Carryover and Alloy Thinking Config

## Problem
Previous tool results can still appear on a later assistant message during streaming, and agent configuration still uses the old `reasoning_effort` contract even though the app now runs on Alloy.

## Approach
1. Patch transcript rendering so synthetic streamed assistant rows only render tool entries that belong to their own declared tool calls.
2. Replace the old reasoning-effort form/runtime contract with an explicit thinking mode setting that maps cleanly to Alloy behavior.
3. Preserve legacy agent records by translating old `reasoning_effort` values into the new thinking setting on load.
4. Update tests around chat streaming, agent forms, and agent changesets, then run targeted suites and `mix precommit`.

## Todos
- Stop orphan or carried-over tool results from rendering on later synthetic assistant rows.
- Migrate agent configuration from reasoning-effort values to a thinking mode setting.
- Adapt Alloy runner/runtime behavior to the new thinking mode.
- Update regressions and validate with repo checks.

## Notes
- No route changes are needed; this work stays within the existing dashboard/chat/agent LiveViews and contexts.
- Keep the setting explicit and binary for users: enabled or disabled.
