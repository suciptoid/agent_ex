## Fix OpenRouter tool-routing failure when tool use is unavailable

- Root issue: some OpenRouter model routes do not support tool use; requests with tool declarations fail with `No endpoints found that support tool use`.
- Added tool capability gating in runner:
  - `App.LLM.Capabilities.tool_use_supported?/2` infers support from cached provider model metadata (`raw.supported_parameters`).
  - Runner now omits tools when the selected model explicitly does not advertise tool-related parameters.
- Added runtime safety fallback:
  - if provider still returns `No endpoints found that support tool use`, runner retries once without tools instead of failing the whole turn.
- Added tests for capability inference:
  - `test/app/llm/capabilities_test.exs`.
- Files changed:
  - `lib/app/llm/capabilities.ex`
  - `lib/app/agents/runner.ex`
  - `test/app/llm/capabilities_test.exs`
- Validation:
  - `mix test test/app/llm/capabilities_test.exs test/app/agents/runner_doom_loop_test.exs test/app/agents/tools_test.exs` (pass)
  - `mix precommit` (pass, 218 tests, 0 failures)

By: gpt-5.2 on Codex CLI
