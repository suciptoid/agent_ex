# Alloy stream tool-output fix

- Removed internal `update_chatroom_title` tool turns from future prompt reconstruction while keeping visible tool calls/results intact.
- Added a streaming Alloy middleware bridge so assistant tool-call turns are emitted before tool execution and persisted with matching tool result rows.
- Changed OpenAI Responses continuation handling to send only messages after the stored `previous_response_id`, avoiding old `function_call_output` replay against a stale response.
- Added an OpenAI-compatible provider wrapper that streams `reasoning_content`/thinking deltas through Alloy `on_event` and preserves final thinking blocks.
- Updated Runner thinking extraction to handle Alloy blocks that use either `thinking` or `text`.
- Added focused coverage for internal title tool filtering, streaming tool-call middleware, and OpenAI-compatible reasoning stream events.
- Verified with focused chat/tool tests, `mix compile --warnings-as-errors`, and `mix precommit`.

By: gpt-5.4 on Codex

## Stream worker position race follow-up

- Routed streaming tool start/result events by `tool_call_id` so late events from a previous Alloy tool turn update the original parent assistant message instead of the current turn.
- Forced creation of the follow-up assistant row before splitting a subsequent tool-call turn, preventing a new tool turn from rewriting the prior assistant tool-call row.
- Threaded updated stream state through completion-time tool sync, avoiding duplicate tool-message inserts at the same position.
- Made final assistant positioning choose the next free transcript position when a reserved target is already occupied.
- Added a regression stub/test that simulates the next tool turn arriving before the previous tool result is handled.
- Re-ran `mix precommit` successfully.

By: gpt-5.4 on Codex

## Main stream tool result live-status follow-up

- Fixed the main chat LiveView path to merge streamed tool start/result events into `streaming_tool_responses` instead of ignoring them.
- Included `streaming_tool_responses` in the temporary assistant placeholder metadata so the tool accordion updates before the final assistant turn completes.
- Preserved existing tool responses when resyncing an active main stream from persisted messages.
- Added a LiveView regression that pauses between tool result emission and final answer streaming, verifying the tool UI no longer remains in the running state.
- Verified with `mix test test/app_web/live/chat_live_test.exs:1039` and `mix test test/app_web/live/chat_live_test.exs`.

By: gpt-5.4 on Codex

## Tool row completion follow-up

- Allowed tool messages to be completed without content so Alloy `tool_end` can update the database status immediately even when the event does not include the tool output text.
- Kept final stream sync as the place that backfills actual tool output content once Alloy exposes the result message.
- Added a stream-worker regression that pauses after tool result emission and verifies the persisted tool row is `completed` before the final assistant turn is allowed to continue.
- Verified with `mix test test/app/chat_test.exs:622`, `mix test test/app/chat_test.exs`, and `mix test test/app_web/live/chat_live_test.exs`.

By: gpt-5.4 on Codex

## Alloy after-tool-execution result follow-up

- Added `:after_tool_execution` handling to `App.Agents.StreamMiddleware`.
- Extracted Alloy `tool_result` and `server_tool_result` blocks after execution and emitted `on_tool_result` payloads with real content before the next model turn.
- Preserved the existing `tool_end` event path as an early status marker; the middleware payload updates the same persisted tool row with output content.
- Added StreamMiddleware tests for successful and errored tool execution result payloads.
- Verified with `mix test test/app/agents/stream_middleware_test.exs` and `mix test test/app/chat_test.exs test/app_web/live/chat_live_test.exs`.

By: gpt-5.4 on Codex
