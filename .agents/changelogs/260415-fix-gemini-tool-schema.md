## Fix Gemini tool schema payload compatibility

- Root cause: Gemini function declaration schema rejects `additionalProperties` in tool parameter schema, and built-in `web_fetch` tool schema included it under `headers`.
- Updated `App.LLM.Client` to build tool definitions with provider-adapter awareness and sanitize schemas for `google`/`gemini` adapters.
- Added recursive schema sanitizer that strips `additionalProperties` before sending tool definitions to Gemini.
- File changed: `lib/app/llm/client.ex`.
- Validation:
  - `mix test test/app/agents/runner_doom_loop_test.exs test/app/agents/tools_test.exs` (pass)
  - `mix precommit` (pass, 215 tests, 0 failures)

By: gpt-5.2 on Codex CLI
