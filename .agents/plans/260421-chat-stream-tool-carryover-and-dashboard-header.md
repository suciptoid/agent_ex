# Plan: Chat Stream Carryover and Dashboard Header

## Problem
The chat transcript can occasionally show a completed tool-call block on the follow-up assistant row that resumes streaming after tool execution. The dashboard hero/header also feels too card-like and visually busy for the product's calm, compact workspace aesthetic.

## Approach
1. Trace the main chat streaming handoff from tool-call row to follow-up assistant row and clear any state that should not survive that switch.
2. Add regression coverage around the tool-turn follow-up row so streamed tool UI stays attached to the originating assistant message.
3. Rework the dashboard header into a cleaner split layout with tighter grouping, clearer hierarchy, and a calmer action area.
4. Run targeted LiveView/chat tests and the project precommit checks, then record the changelog.

## Todos
- Fix the chat stream handoff so tool UI does not bleed into the next assistant row.
- Add or expand regression coverage for the tool-turn follow-up transcript behavior.
- Refresh the dashboard header layout and keep existing route/layout usage unchanged.
- Validate the affected tests and `mix precommit`.

## Notes
- The dashboard route remains in the existing browser scope and `DashboardLive`; this is a layout/content refinement, not a routing change.
- Preserve the current compact product feel from `.impeccable.md`: calm, compact, simple.
