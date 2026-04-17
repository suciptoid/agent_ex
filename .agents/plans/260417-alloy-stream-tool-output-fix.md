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

## Tool result live status follow-up

Main chat LiveView tool start/result events were persisted but not reflected in the streamed placeholder because `put_main_stream_tool_response/2` ignored the event and the main stream metadata omitted `streaming_tool_responses`.

1. Include main stream tool responses in placeholder metadata.
2. Merge incoming main stream tool start/result events into `streaming_tool_responses` and re-stream the placeholder immediately.
3. Preserve persisted tool responses when syncing an active main stream from the database.
4. Add a LiveView regression that pauses after a tool result and before the final answer, asserting the tool UI leaves the running state immediately.

## Tool DB status follow-up

Alloy `tool_end` events can report that execution is finished before the final result message exposes the tool output text. The stream worker attempted to mark the tool row completed with blank content, but the message changeset rejected completed rows without content, leaving the database row pending until final sync.

1. Allow `role: "tool"` messages to be completed without content.
2. Keep final result sync responsible for backfilling tool output content when Alloy exposes it.
3. Add a stream-worker regression that pauses after tool result emission and asserts the database tool row is `completed` before the final assistant turn continues.

## Alloy after-tool-execution follow-up

`tool_end` is a low-level execution event and only carries metadata. Alloy's `:after_tool_execution` middleware hook runs after `Message.tool_results(...)` has been appended to state, so it can stream the actual tool output content before the next model turn.

1. Handle `:after_tool_execution` in `App.Agents.StreamMiddleware`.
2. Extract the latest tool result message from Alloy state and emit `on_tool_result` payloads with id, name, arguments, content, and status.
3. Keep `tool_end` support as an early status marker; the middleware result payload updates the same tool row with content.
4. Add middleware tests for successful and errored tool result payloads.
