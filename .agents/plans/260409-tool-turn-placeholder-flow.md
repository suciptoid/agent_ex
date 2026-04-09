# Tool-turn placeholder flow

1. Move follow-up assistant placeholder creation later in the stream worker so tool-only turns do not create an empty second assistant row before tool execution finishes.
2. Restore normal pending-message visibility and loading indicator behavior in the chat LiveView once a pending assistant message actually exists.
3. Extract concise user-facing error text by preferring nested `reason` values over inspected exception structs.
4. Verify with focused chat tests and `mix precommit`, then record the changelog.
