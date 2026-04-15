# ReqLLM to Alloy migration plan

## Goal

Migrate the app from `req_llm`/`llm_db` to Alloy while preserving current chat, streaming, tools, and provider workflows.

## Why this migration

- `req_llm` depends on `llm_db`, and model/provider catalogs drift quickly.
- Alloy gives a stable provider abstraction layer and is easier to extend for custom API endpoints.
- We need provider-level model refresh from provider APIs (`/models`) so model catalogs are app-owned and updatable without waiting on library releases.

## Non-goals

- Rewriting chat UX or multi-agent orchestration behavior.
- Changing auth/session routing behavior.
- Migrating historical chat data format.

## Current coupling (inventory)

- Core runtime:
  - `lib/app/agents/runner.ex` (ReqLLM context building, streaming, classify/usage).
  - `lib/app/chat/compaction.ex` (ReqLLM summarize checkpoint).
- Tooling:
  - `lib/app/agents/tools.ex` (`ReqLLM.tool`, `ReqLLM.Tool.execute`).
  - `lib/app/chat/orchestrator.ex` (`ReqLLM.tool` for `handover`, `ask_agent`, `update_chatroom_title`).
  - `lib/app/tools/tool.ex` (`ReqLLM.Tool.valid_name?/1`).
- Provider/model catalog:
  - `lib/app/providers.ex` (`LLMDB.providers`, `ReqLLM.Provider.Generated.ValidProviders`).
  - `lib/app_web/live/agent_live/form_component.ex` (`ReqLLM.available_models/2`).
  - `lib/app_web/live/chat_live/show.ex` and `lib/app/agents/runner.ex` (`ReqLLM.model` + reasoning support helper).
- Config/deps:
  - `mix.exs`, `config/config.exs`, `mix.lock`.

## Target architecture

### 1) Introduce app-owned LLM boundary (keep `App.Agents.Runner` public API stable)

Add `App.LLM` namespace so app logic stops calling `ReqLLM` directly:

- `App.LLM.Client` (behaviour):
  - `complete(model, messages, opts)`
  - `stream(model, messages, opts, callbacks)`
  - returns normalized payload expected by existing orchestrator/stream worker.
- `App.LLM.Backend.ReqLLM` (temporary compatibility backend).
- `App.LLM.Backend.Alloy` (new backend using Alloy providers).
- `App.LLM.Messages`:
  - App message map ↔ `Alloy.Message` conversion.
- `App.LLM.Tools`:
  - app-owned tool definition struct + executor (remove hard dependency on `ReqLLM.Tool`).
- `App.LLM.ModelCapabilities`:
  - reasoning support + context window lookup from cached model metadata, with conservative fallback.
- `App.LLM.Errors`:
  - normalize provider errors to existing user-facing shape.

Result: `App.Agents.Runner`, `App.Chat.Compaction`, `App.Agents.Tools`, and LiveViews only depend on `App.LLM.*`.

### 2) Provider model owned by app (not library catalogs)

Expand provider storage so each provider can point to custom endpoint and refresh models:

- Extend `providers` table:
  - `adapter` (e.g. `openai`, `openai_compat`, `anthropic`, `gemini`, `custom_openai_compat`)
  - `base_url`
  - `models_path` (default `/models` or provider-default)
  - `chat_path` (for OpenAI-compatible chat endpoints)
  - `extra_headers` (encrypted map)
  - `extra_body` (provider-specific defaults, optional)
  - `models_last_refreshed_at`
  - `models_last_refresh_error`
- New `provider_models` table:
  - `provider_id`, `model_id`, `label`, `raw`, `supports_reasoning`, `context_window`, timestamps
  - unique index on `{provider_id, model_id}`.

### 3) Model refresh service

Add `App.Providers.ModelSync`:

- `refresh_provider_models(provider)` fetches `GET #{base_url}#{models_path}` with `Req`.
- Adapter-specific parsers normalize vendor payloads to `provider_models` rows.
- Upsert models; track refresh status/error on provider.
- Keep operation idempotent and safe for manual retry.

## Router / auth scope decision

No new public route is required.

Model refresh is triggered from existing provider management LiveViews (`ProviderLive`) that already run inside:

- `pipe_through [:browser, :require_authenticated_user, :active_organization_required]`
- `live_session :require_active_organization`

This preserves `current_scope` assignment and organization guardrails without introducing new unauthenticated surfaces.

## Migration phases (low-risk)

### Phase 0 — Baseline + guardrails

1. Add high-signal regression tests around current behavior (before migration):
   - streaming token flow
   - tool call turns + tool result persistence
   - delegated `ask_agent` flow
   - compaction fallback behavior
   - provider form + model selection behavior.
2. Add runtime feature flag:
   - `config :app, :llm_backend, :req_llm | :alloy`.

### Phase 1 — Extract abstraction with no behavior change

1. Create `App.LLM` boundary + ReqLLM backend implementation.
2. Refactor all direct ReqLLM/LLMDB callers to `App.LLM.*`.
3. Keep tests green; no functional changes yet.

### Phase 2 — Provider/model schema + refresh workflow

1. Add migrations for provider config fields + `provider_models`.
2. Backfill existing providers:
   - map current `provider` string to default `adapter/base_url/models_path/chat_path`.
3. Implement `ModelSync` service + parser modules.
4. Update Provider UI:
   - show adapter + endpoint settings.
   - add “Refresh models” action + last refresh status.
5. Update Agent form to read models from `provider_models` cache.
   - keep manual model entry fallback if refresh/cache empty.

### Phase 3 — Alloy backend implementation

1. Implement `App.LLM.Backend.Alloy` using Alloy providers:
   - provider resolver: DB provider config -> `{Alloy.Provider.*, config}`.
   - message conversion: app messages/tool results <-> `Alloy.Message` blocks.
   - stream + complete mapping into existing runner result shape.
2. Keep `App.Agents.Runner` public contract unchanged (`content`, `thinking`, `tool_call_turns`, `tool_responses`, `usage`, `finish_reason`, `provider_meta`).
3. Replace ReqLLM-only tool primitives with app-owned tool definitions/executor.
4. Replace `ReqLLM.Tool.valid_name?/1` with app regex validation (same identifier constraints).

### Phase 4 — Cutover and cleanup

1. Switch `:llm_backend` default to `:alloy`.
2. Run full regression (`mix precommit`) and fix issues.
3. Remove `req_llm` + `llm_db` deps/config and dead adapters.
4. Keep rollback path for one release window by retaining feature flag toggle.

## Behavior parity checklist (must pass before cutover)

- Runner:
  - tool-loop behavior and doom-loop detection unchanged.
  - sync/streaming callbacks unchanged (`on_result`, `on_thinking`, `on_tool_calls`, `on_tool_start`, `on_tool_result`).
- Persistence:
  - same chat message/tool message shape.
  - same metadata keys (`usage`, `thinking`, `tool_calls`, `finish_reason`, `provider_meta`).
- Compaction:
  - checkpoint generation + fallback still works.
- Multi-agent:
  - `handover`, `ask_agent`, `update_chatroom_title` tool flows preserved.
- UI:
  - provider creation/edit still works for existing providers.
  - agent creation/edit model selection still works when cache present and when empty.
- Errors:
  - user-facing error text remains concise and normalized.

## Key risks and mitigations

1. **Tool execution contract drift**
   - Mitigation: introduce app-owned tool contract first, then swap backend.
2. **Streaming semantics mismatch**
   - Mitigation: preserve callback contract and add stream-focused tests for each event type.
3. **Reasoning support regressions**
   - Mitigation: centralize in `ModelCapabilities` with cached model capability + fallback heuristics.
4. **Provider model refresh parser fragmentation**
   - Mitigation: parser-per-adapter modules + raw payload persistence for diagnostics.
5. **Migration/backfill mistakes on existing providers**
   - Mitigation: deterministic backfill map + data migration test.
6. **UI blocked when no cached models**
   - Mitigation: allow manual model input fallback.
7. **Error-message regressions breaking UX/tests**
   - Mitigation: normalize errors in one module and add contract tests.
8. **Hard cutover risk**
   - Mitigation: feature-flagged dual backend and staged rollout.

## Test strategy

- Unit tests:
  - `App.LLM.Messages`, `App.LLM.ProviderResolver`, model refresh parsers, capability lookup.
- Integration tests:
  - `App.Agents.Runner` sync/streaming parity with stubbed providers.
  - `App.Chat.Orchestrator` tool turn persistence + delegated flows.
- LiveView tests:
  - provider refresh action and model list rendering.
  - agent form creation/edit with refreshed and manual models.
- Migration tests:
  - existing provider rows backfilled correctly.
- Final gate:
  - `mix precommit` clean on Alloy-default backend.

## Rollout / rollback

- Rollout:
  1. Deploy with ReqLLM backend default + Alloy backend available.
  2. Refresh provider models for active orgs.
  3. Enable Alloy backend in staging and then production.
- Rollback:
  - flip `:llm_backend` back to `:req_llm` until issue resolved.

## Deliverables

1. New `App.LLM` abstraction and Alloy backend.
2. Provider schema + `provider_models` cache.
3. Model refresh service (`/models` support) + provider UI refresh controls.
4. Backward-compatible runner/orchestrator behavior.
5. Removed `req_llm`/`llm_db` dependencies after cutover.
