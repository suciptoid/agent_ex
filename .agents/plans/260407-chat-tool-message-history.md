# Chat Tool Message History

- refactor chat persistence to store the **real** agentic transcript, not a synthesized one
- persist separate rows for:
  - assistant turn that requests tools
  - each tool result
  - final assistant turn after tool results
- update the UI so those persisted rows render as the real conversation flow instead of collapsing tool work into a single assistant message

## Work
- keep standalone tool message support, but stop hiding tool rows behind assistant-message projections
- change the streaming worker/orchestrator loop so tool-call detection finalizes the current assistant message and starts a new assistant placeholder for the final answer
- switch the active running message/registry tracking when the stream advances from assistant turn 1 to assistant turn 2
- simplify context rebuilding to replay the real stored transcript order
- update LiveView rendering/tests to assert assistant(tool_calls) -> tool -> assistant(final)

## Outcome
- the persisted transcript now stores the real tool loop as `assistant(tool_calls) -> tool -> assistant(final)` in both non-streaming and streaming paths
- the stream worker hands off the active registry key to the final assistant turn, preserves ordered positions, and stops the UI from reintroducing legacy `tool_responses` metadata during streaming
- chat LiveView and chat tests now read/render the real transcript rows directly, while legacy metadata helpers remain as fallback for older records
