# Alloy stream tool-output fix

- Removed internal `update_chatroom_title` tool turns from future prompt reconstruction while keeping visible tool calls/results intact.
- Added a streaming Alloy middleware bridge so assistant tool-call turns are emitted before tool execution and persisted with matching tool result rows.
- Changed OpenAI Responses continuation handling to send only messages after the stored `previous_response_id`, avoiding old `function_call_output` replay against a stale response.
- Added an OpenAI-compatible provider wrapper that streams `reasoning_content`/thinking deltas through Alloy `on_event` and preserves final thinking blocks.
- Updated Runner thinking extraction to handle Alloy blocks that use either `thinking` or `text`.
- Added focused coverage for internal title tool filtering, streaming tool-call middleware, and OpenAI-compatible reasoning stream events.
- Verified with focused chat/tool tests, `mix compile --warnings-as-errors`, and `mix precommit`.

By: gpt-5.4 on Codex

