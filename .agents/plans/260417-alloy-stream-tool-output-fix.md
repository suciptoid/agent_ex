# Alloy stream tool-output fix

## Problem

Streaming can fail with an OpenAI-compatible Responses API error:

`No tool call found for function call output with call_id ...`

The likely cause is replaying a persisted internal tool output, especially `update_chatroom_title`, without replaying the matching assistant tool-call item in the exact shape/provider context expected by Alloy/OpenAI.

The Alloy migration also appears to have regressed live thinking/reasoning deltas for at least some OpenAI-compatible providers such as `stepfun-3.5-flash`.

## Plan

1. Inspect the prior Alloy migration plan/changelog and the current runner/message conversion/persistence flow.
2. Reproduce or add a focused regression around persisted internal title tool calls being replayed into Alloy input.
3. Patch message reconstruction so internal tool-call outputs do not create orphan provider tool-result items while still preserving visible tool history.
4. Restore streaming thinking/reasoning callbacks from Alloy stream events or provider chunks.
5. Run focused tests and then `mix precommit`.

## Result

Completed. The prompt reconstruction now filters internal title tools, streaming emits assistant tool-call turns before tool execution, OpenAI Responses continuation no longer replays older tool outputs, and OpenAI-compatible reasoning deltas are streamed into the existing thinking callback path.

## Follow-up

Fixed a stream worker ordering race where tool events from Alloy worker tasks could arrive after the next assistant tool turn. Tool results are now routed by `tool_call_id` to the correct parent assistant turn, follow-up assistant rows are created before splitting a subsequent tool turn, sync-time tool persistence threads the updated stream state forward, and final assistant positioning chooses the next free transcript position.
