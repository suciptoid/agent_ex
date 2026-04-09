# Tool Call Placeholder Visibility

1. Inspect chat streaming placeholder logic and identify the condition that renders the assistant loading placeholder during pending tool execution.
2. Update the LiveView so pending assistant placeholders remain hidden while earlier tool calls are still incomplete and no assistant text/thinking stream has started.
3. Add or update LiveView coverage for the tool-running transcript state.
4. Verify with focused tests and `mix precommit`, then record results in the changelog.
