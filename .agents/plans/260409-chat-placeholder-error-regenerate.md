# Chat placeholder, error, and regenerate behavior

1. Hide the entire main assistant placeholder row while prior tool calls are still running and the assistant has not started thinking or streaming content.
2. Sanitize user-facing error text so exceptions and nested error tuples surface only their message text.
3. Make regenerate/retry use the room's current active agent when it differs from the original message agent.
4. Add regression coverage and validate with targeted tests plus `mix precommit`.
