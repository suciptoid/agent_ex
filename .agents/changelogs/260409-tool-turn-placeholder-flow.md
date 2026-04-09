## Tool-turn placeholder flow

- Updated [stream_worker.ex](/Users/sucipto/Developer/agent_ex/lib/app/chat/stream_worker.ex) so assistant follow-up placeholder rows are no longer created immediately inside `split_assistant_turn/2`. The worker now defers creation until tool results for that turn have completed, then switches the live stream to the new pending assistant message.
- Restored normal pending-row visibility and loading-indicator behavior in [show.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/chat_live/show.ex): if a pending main assistant message exists, it renders normally with the streaming indicator again.
- Changed reasoning option forwarding in [show.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/chat_live/show.ex) so the `"default"` UI selection omits the `reasoning_effort` request param instead of sending an invalid `:default` value to the provider.
- Tightened surfaced error extraction in [show.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/chat_live/show.ex), [stream_worker.ex](/Users/sucipto/Developer/agent_ex/lib/app/chat/stream_worker.ex), [runner.ex](/Users/sucipto/Developer/agent_ex/lib/app/agents/runner.ex), and [orchestrator.ex](/Users/sucipto/Developer/agent_ex/lib/app/chat/orchestrator.ex) to prefer nested `reason` text over inspected exception structs or full API payloads.
- Added regression coverage in [chat_live_test.exs](/Users/sucipto/Developer/agent_ex/test/app_web/live/chat_live_test.exs) for deferred follow-up placeholder creation after tool results, omitted default reasoning effort, active-agent-aware regenerate behavior, and concise ReqLLM API error rendering. Added [tool_turn_pause_runner_stub.ex](/Users/sucipto/Developer/agent_ex/test/support/stubs/tool_turn_pause_runner_stub.ex) to pause between tool results and assistant follow-up output.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- `mix test test/app/chat_test.exs`
- `mix precommit`

By: gpt-5.4 on Codex
