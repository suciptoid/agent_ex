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
