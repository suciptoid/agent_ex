# Alloy Migration: req_llm → alloy

## Summary

Complete migration of LLM infrastructure from `req_llm` + `LLMDB` to `alloy` library.

## Changes

### Dependencies
- Replaced `{:req_llm, "~> 1.6"}` with `{:alloy, "~> 0.9"}` in mix.exs
- Removed `config :req_llm` block from config.exs
- Unlocked 15+ unused transitive dependencies (req_llm, llm_db, etc.)

### Schema & Migrations
- Added `base_url` and `provider_type` fields to Provider schema
- Auto-infers `provider_type` from `provider` name (anthropic/openai → direct, others → openai_compat)
- Migration backfills existing providers and strips `provider:model` → just `model` in agents table
- Removed `provider:model` format validation from Agent changeset

### Provider System
- Created `AlloyConfig` module mapping Provider records → Alloy provider tuples
- Created `Models` module with API-fetch + static fallback model lists
- Rewrote `Providers` context: removed LLMDB/ValidProviders, uses static provider_types
- Updated provider form UI: added base_url and provider_type fields

### Tool System
- Created 7 Alloy tool modules implementing `@behaviour Alloy.Tool`:
  - `WebFetch`, `Shell`, `CreateTool`, `HttpTool`, `Handover`, `AskAgent`, `UpdateTitle`
- Rewrote `Tools.resolve/2` for Alloy tool resolution
- Removed `Tools.execute_all/3` (Alloy handles tool execution loop)
- `execute_http_tool/2` now accepts both `%HttpTool{}` and `%Tool{}` structs

### Core Engine
- **Runner**: Complete rewrite using `Alloy.run/2` and `Alloy.stream/3`
  - Removed entire tool execution loop (Alloy handles via `max_turns`)
  - Removed DoomLoop dependency (replaced by Alloy's built-in turn limits)
  - New message conversion: `Message` → `Alloy.Message` format
- **Compaction**: Rewrote to use `Alloy.run` with `max_turns: 1` for LLM summaries
- **Orchestrator**: Replaced tool builders with Alloy tool modules + context map pattern
  - AskAgent delegation uses `run_delegated_agent` function in context map
  - Cleaned up unused private functions

### Context Builder
- Updated model override patterns: `"anthropic:claude-*"` → `"claude-*"`, etc.

### UI
- Reasoning effort: now always respects agent setting regardless of model detection
- Removed model-based reasoning pattern matching (was ReqLLM-dependent)
- Agent form: model options fetched from `Models.list_models`
- Provider form: added base_url + provider_type fields

### Deleted Files
- `lib/app/agents/runner/doom_loop.ex`
- `test/app/agents/runner_doom_loop_test.exs`

### Test Updates
- Updated all model references from `"provider:model"` → `"model"` format
- Updated provider tests for new behavior (accepts any provider name)
- Updated tools tests (removed execute_all, fixed HttpTool assertions)
- Updated chat_live reasoning tests for new behavior
- Updated 3 test stubs (removed all ReqLLM references)
- All 211 tests pass, `mix precommit` green

By: claude-opus-4.6 on Github Copilot
