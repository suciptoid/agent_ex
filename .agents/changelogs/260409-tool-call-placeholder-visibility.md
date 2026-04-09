## Tool call placeholder visibility

- Changed the chat transcript loading-indicator rule in [show.ex](/Users/sucipto/Developer/agent_ex/lib/app_web/live/chat_live/show.ex) so pending assistant messages no longer render the assistant placeholder dots while the model is still waiting on earlier tool output.
- Kept tool progress visible through the existing tool accordion entry, and only allow the assistant placeholder indicator to appear once assistant thinking/content streaming has actually started.
- Added a LiveView regression test in [chat_live_test.exs](/Users/sucipto/Developer/agent_ex/test/app_web/live/chat_live_test.exs) covering a pending assistant message with a running tool response and no assistant text yet.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- `mix precommit`

By: gpt-5.4 on Codex
