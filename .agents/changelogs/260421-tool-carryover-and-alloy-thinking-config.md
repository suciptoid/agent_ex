## Tool carryover and Alloy thinking config

- Fixed the remaining transcript leak by making streamed assistant placeholder maps carry both `tool_calls` and `tool_responses`, then limiting orphan tool-response rendering to persisted assistant messages only. That keeps waiting/running tool rows visible on the correct tool-call turn without duplicating them on the follow-up assistant message.
- Replaced the old `reasoning_effort` agent form contract with a binary `thinking_mode` setting (`enabled` / `disabled`) and store the normalized choice in `extra_params["thinking"]`.
- Added backward-compatible loading so legacy agents with old `reasoning_effort` values still reopen in the new form with `thinking_mode: "enabled"` when appropriate.
- Updated the Alloy runner to interpret `thinking_mode`, request Anthropic `extended_thinking` only when enabled, and suppress streamed/final thinking blocks when the agent has thinking disabled.
- Updated agent context, LiveView form, and chat tests to cover the new thinking-mode setting and the synthetic streamed tool-row regression.
- Verified with focused agent/chat suites and `mix precommit`.

By: gpt-5.4 on Github Copilot
