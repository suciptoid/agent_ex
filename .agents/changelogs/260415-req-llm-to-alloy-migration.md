## ReqLLM → Alloy migration planning

- Audited all current `ReqLLM`/`LLMDB` coupling points across runtime, tools, provider catalogs, and LiveViews.
- Reviewed Alloy provider/runtime capabilities and confirmed it supports configurable provider base URLs and OpenAI-compatible `chat_path`, but model discovery (`/models`) should stay app-owned via `Req`.
- Produced a phased migration plan that preserves current workflows using an app-owned `App.LLM` boundary and a compatibility period (`ReqLLM` adapter first, Alloy adapter behind feature flag).
- Planned provider model refresh with custom endpoint support and a `provider_models` cache so model updates are no longer blocked by upstream library catalogs.
- Included parity checklist, staged rollout/rollback, and top migration risks with mitigations.
- Integrated senior-agent advice for boundary design, phased cutover, and test strategy.

Plan file:
- `.agents/plans/260415-req-llm-to-alloy-migration.md`

By: gpt-5.2 on Codex

## Execution summary (implementation)

- Replaced `req_llm` runtime usage with app-owned `App.LLM` boundary and Alloy-backed client modules under `lib/app/llm/`.
- Migrated runner, compaction, and tool plumbing to `App.LLM.Client` while preserving existing orchestrator/tool callback workflow.
- Reworked providers to app-owned model catalogs:
  - added provider endpoint fields in `providers`
  - added `provider_models` cache table
  - implemented `/models` refresh + upsert flow in `App.Providers`.
- Updated Provider and Agent LiveViews to support endpoint config, model refresh, and cached model selection fallback.
- Removed `req_llm`/`llm_db` dependency path, added `alloy`, and cleaned obsolete config.
- Added migration: `priv/repo/migrations/20260415050000_add_alloy_provider_fields_and_models.exs`.
- Updated affected tests/stubs for new tool/client contracts.
- Validation: `mix precommit` passed (215 tests, 0 failures).

By: gpt-5.2 on Codex CLI
