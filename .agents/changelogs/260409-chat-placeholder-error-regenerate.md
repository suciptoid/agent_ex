## Chat placeholder, error, and regenerate behavior

- Updated [show.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/chat_live/show.ex) so the main assistant row stays out of the transcript while earlier tool calls are still running and the assistant has not started emitting thinking or content. That hides the full placeholder row, including avatar and agent name, not just the loading dots.
- Changed regenerate/retry to reuse the room's current active agent instead of the original message agent when they differ, so reruns follow the active agent selection at click time.
- Replaced verbose `inspect/1` style user-facing error text with extracted exception or nested error messages in [show.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/chat_live/show.ex), [stream_worker.ex](/Users/sucipto/Developer/agent_ex/lib/app/chat/stream_worker.ex), and [orchestrator.ex](/Users/sucipto/Developer/agent_ex/lib/app/chat/orchestrator.ex).
- Added regression coverage in [chat_live_test.exs](/Users/sucipto/Developer/agent_ex/test/app_web/live/chat_live_test.exs) for hidden main placeholders during running tool calls, regenerate switching to the active agent, and sanitized failed-run error content. Added [failing_agent_runner_stub.ex](/Users/sucipto/Developer/agent_ex/test/support/stubs/failing_agent_runner_stub.ex) for the error case.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- `mix precommit`

By: gpt-5.4 on Codex
