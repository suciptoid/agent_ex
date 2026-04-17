# Migration Plan: req_llm → alloy

## Problem
The app currently uses `req_llm` (+ `LLMDB`) for LLM integration: streaming, tool definitions, context building, response classification, provider metadata, and model listing. We want to replace it with [alloy](https://github.com/alloy-ex/alloy) — a model-agnostic, OTP-native agent harness that owns the completion-tool-call loop, context compaction, and parallel tool execution natively.

## Key Trade-offs
- **Gains**: Alloy owns the agentic turn loop (`max_turns`), built-in compaction, parallel tool execution via `Task.Supervisor`, middleware hooks, retry/fallback providers, token budgeting, telemetry events, and a clean `Alloy.Tool` behaviour.
- **Losses**: No models database (LLMDB). We must manage model lists ourselves — either fetch from API or let users define models manually.

## Approach
Incremental migration, one layer at a time. Each phase is independently testable.

---

## Phase 1: Dependencies & Provider Schema Changes

### 1.1 Swap deps in mix.exs
- Remove `{:req_llm, "~> 1.6"}` from deps
- Add `{:alloy, "~> 0.9"}` to deps  
- Keep `{:req, "~> 0.5"}` (alloy uses Req internally, our HTTP tools still need it)
- Run `mix deps.get`

### 1.2 Update Provider schema
Current `providers` table stores: `name`, `provider` (string like "openai"), `api_key` (encrypted).  
Add new columns via migration:
- `base_url` (string, nullable) — custom API endpoint for OpenAICompat providers
- `provider_type` (string, nullable) — one of: `"openai"`, `"anthropic"`, `"openai_compat"` — maps to Alloy provider module
  - For existing providers, infer `provider_type` from `provider` field (e.g. `"openai"` → `"openai"`, `"anthropic"` → `"anthropic"`, everything else → `"openai_compat"`)
- Keep the existing `provider` field as the provider identifier/label

### 1.3 Update Provider form UI
- Add optional "Base URL" input field (shown when provider_type is `openai_compat` or user enables "Custom URL" toggle)
- Add a `provider_type` select: OpenAI, Anthropic, OpenAI Compatible
- When `provider_type` is `openai_compat`, show base_url as required

### 1.4 Provider → Alloy mapping helper
Create `App.Providers.AlloyConfig` module:
```elixir
def to_alloy_provider(%Provider{} = provider, model_name, extra_opts \\ []) do
  base_opts = [api_key: provider.api_key, model: model_name] ++ extra_opts
  
  case provider_type(provider) do
    "anthropic" -> {Alloy.Provider.Anthropic, base_opts ++ maybe_base_url(provider)}
    "openai" -> {Alloy.Provider.OpenAI, base_opts ++ maybe_api_url(provider)}
    "openai_compat" -> {Alloy.Provider.OpenAICompat, [api_url: provider.base_url | base_opts]}
    _ -> {Alloy.Provider.OpenAICompat, base_opts ++ maybe_api_url(provider)}
  end
end
```

---

## Phase 2: Tool System Migration

### 2.1 Create Alloy Tool wrappers for builtin tools
Convert each builtin tool to an `Alloy.Tool` behaviour module:

- `App.Agents.AlloyTools.WebFetch` — implements `@behaviour Alloy.Tool`
  - `name/0` → `"web_fetch"`
  - `description/0` → existing description
  - `input_schema/0` → JSON Schema map (same as current)
  - `execute/2` → calls existing `App.Agents.Tools.do_web_fetch/1`

- `App.Agents.AlloyTools.Shell` — same pattern, wraps `do_shell/1`

- `App.Agents.AlloyTools.CreateTool` — wraps `do_create_tool/2`
  - Needs `organization_id` from context: `execute(input, %{organization_id: org_id})`

### 2.2 Create dynamic tool wrapper for custom HTTP tools
- `App.Agents.AlloyTools.HttpTool` — a module that can build Alloy tool structs dynamically from `App.Tools.Tool` records
- Since Alloy tools are modules implementing a behaviour, we'll create a factory that returns anonymous tool maps or use a generic wrapper module with context

### 2.3 Update tool resolution
- `App.Agents.Tools.resolve/2` returns list of Alloy tool modules/structs instead of ReqLLM tools
- `App.Agents.Tools.execute_all/2` — likely removed, as Alloy's `Tool.Executor` handles this

---

## Phase 3: Runner Migration (Core)

### 3.1 Replace Runner with Alloy.run/2
The current `Runner.run_streaming/4` implements a manual tool loop. Alloy's `Alloy.run/2` with `max_turns` replaces this entirely.

New `App.Agents.Runner`:
```elixir
def run(agent, messages, opts \\ []) do
  alloy_messages = build_alloy_messages(agent, messages, opts)
  tools = resolve_alloy_tools(agent, opts)
  provider = build_alloy_provider(agent, opts)
  
  Alloy.run(alloy_messages,
    provider: provider,
    tools: tools,
    system_prompt: build_system_prompt(agent, opts),
    max_turns: 25,
    # extra params
    ...merge_extra_params(agent)
  )
end
```

### 3.2 Streaming via Alloy
For streaming, use `Alloy.stream/3` or provider-level `on_chunk` callback:
```elixir
def run_streaming(agent, messages, recipient, opts) do
  on_chunk = fn text_delta -> send(recipient, {:stream_chunk, text_delta}) end
  
  # Alloy provider config includes on_event for streaming
  provider = build_alloy_provider(agent, opts ++ [on_chunk: on_chunk])
  
  Alloy.run(messages_list,
    provider: provider,
    tools: tools,
    max_turns: 25
  )
end
```

### 3.3 Streaming callbacks mapping
Map current callback events to Alloy's middleware/event system:
- `on_result` (text tokens) → provider's `on_chunk` callback
- `on_thinking` (thinking tokens) → provider's thinking block events  
- `on_tool_calls` → Alloy middleware `:after_tool_request` hook
- `on_tool_start` → Alloy middleware `:before_tool_call` hook
- `on_tool_result` → Alloy middleware `:after_tool_execution` hook

Create `App.Agents.StreamMiddleware` implementing `Alloy.Middleware`:
```elixir
defmodule App.Agents.StreamMiddleware do
  @behaviour Alloy.Middleware
  
  def call(:before_tool_call, state) do
    # notify on_tool_start
    state
  end
  
  def call(:after_tool_execution, state) do
    # notify on_tool_result  
    state
  end
  
  def call(_hook, state), do: state
end
```

### 3.4 Remove DoomLoop detection
Alloy has `max_turns` built in, which serves as the loop safety net. Remove `App.Agents.Runner.DoomLoop` module.

---

## Phase 4: Context & Compaction Migration

### 4.1 Message format conversion
Create `App.Chat.AlloyMessages` module:
- Convert `App.Chat.Message` → `Alloy.Message` structs
- Handle role mapping: `"user"` → `:user`, `"assistant"` → `:assistant`
- Handle tool messages: use `Alloy.Message.tool_results/1`
- Handle checkpoint messages: convert to system-like messages

### 4.2 Compaction migration
Alloy has built-in compaction via `Alloy.Context.Compactor`. Options:
```elixir
compaction: [
  reserve_tokens: 16_384,
  keep_recent_tokens: 20_000,
  fallback: :truncate
]
```

However, our compaction is app-level (persists checkpoints to DB). We have two options:
- **Option A**: Use Alloy's compaction for the LLM context window, keep our DB checkpoints separately
- **Option B**: Use Alloy's `on_compaction` callback to persist checkpoint summaries

Recommend **Option A+B hybrid**: Let Alloy handle context window management, use `on_compaction` to persist checkpoints to our DB, and simplify `ContextBuilder` to just convert DB messages → Alloy messages.

### 4.3 Simplify ContextBuilder  
The complex token budgeting in `ContextBuilder` becomes much simpler since Alloy handles compaction internally. `ContextBuilder.prepare/4` becomes a thin adapter that:
1. Loads messages from DB
2. Converts to `Alloy.Message` format
3. Passes to Alloy with compaction config

---

## Phase 5: Orchestrator & StreamWorker Updates

### 5.1 Update Orchestrator
- Replace `agent_runner().run(...)` / `agent_runner().run_streaming(...)` calls with Alloy-based runner
- Multi-agent tools (`handover`, `ask_agent`) become `Alloy.Tool` behaviour modules with context
- Title tool becomes an `Alloy.Tool` behaviour module
- Simplify `run_with_context_control` — Alloy handles context overflow via compaction

### 5.2 Update StreamWorker
- Adapt to receive Alloy streaming events instead of ReqLLM streaming events
- The callback interface (on_result, on_tool_calls, etc.) stays the same at the StreamWorker level
- Internal streaming events come from Alloy's `on_chunk`/middleware

### 5.3 Result format adaptation
Create adapter from `Alloy.Result` → our internal result map:
```elixir
def from_alloy_result(%Alloy.Result{} = result) do
  %{
    content: result.text,
    thinking: extract_thinking(result),
    tool_call_turns: extract_tool_turns(result),
    tool_responses: extract_tool_responses(result),
    usage: result.usage,
    finish_reason: to_string(result.status),
    provider_meta: result.metadata
  }
end
```

---

## Phase 6: Model Selection & Agent Settings

### 6.1 Model listing without LLMDB
Since alloy has no model database, we need to provide model lists ourselves.

**Approach**: 
- For providers that support it (OpenAI, Anthropic), fetch models from API using `Req.get` to their models endpoint
- Create `App.Providers.Models` module with:
  - `list_models(provider)` — fetches available models from API
  - `known_models(provider_type)` — fallback static list of common models
- Add a "Custom model" text input option so users can type any model identifier
- Use Alloy's `model_metadata_overrides` for custom models

### 6.2 Update Agent form
- Model dropdown: populated from `App.Providers.Models.list_models/1`
- Add "Custom model" option that shows a text input
- Change model storage: Currently stores `"provider:model"` format. Change to just store model name (e.g. `"gpt-4o"`) since provider is already linked via `provider_id`

### 6.3 Agent schema change
- Remove the `provider:model` format validation
- Model field stores just the model name
- Migration to strip `provider:` prefix from existing model values

---

## Phase 7: Cleanup & Testing

### 7.1 Remove ReqLLM/LLMDB references
- Remove all `ReqLLM.*` calls across the codebase
- Remove `LLMDB` references from `App.Providers`
- Remove `App.Agents.Runner.DoomLoop`
- Clean up unused context builder complexity

### 7.2 Update test stubs
- Update `AgentRunnerStub` and all test stubs to match new Alloy-based interface
- Use `Alloy.Testing` helpers where appropriate
- Update `ChatCompactionStub`

### 7.3 Run precommit
- `mix precommit` to verify everything compiles, formats, and tests pass

---

## File Impact Summary

### New files:
- `lib/app/providers/alloy_config.ex` — Provider → Alloy config mapper
- `lib/app/providers/models.ex` — Model listing (API fetch + static fallback)
- `lib/app/agents/alloy_tools/web_fetch.ex` — Alloy Tool behaviour
- `lib/app/agents/alloy_tools/shell.ex` — Alloy Tool behaviour
- `lib/app/agents/alloy_tools/create_tool.ex` — Alloy Tool behaviour
- `lib/app/agents/alloy_tools/http_tool.ex` — Dynamic HTTP tool wrapper
- `lib/app/agents/alloy_tools/handover.ex` — Multi-agent handover tool
- `lib/app/agents/alloy_tools/ask_agent.ex` — Multi-agent delegation tool
- `lib/app/agents/alloy_tools/update_title.ex` — Chat room title update tool
- `lib/app/agents/stream_middleware.ex` — Alloy Middleware for streaming events
- `lib/app/chat/alloy_messages.ex` — Message format adapter
- `priv/repo/migrations/*_add_provider_fields_for_alloy.exs` — Schema migration
- `priv/repo/migrations/*_update_agent_model_format.exs` — Model format migration

### Modified files:
- `mix.exs` — deps swap
- `lib/app/providers/provider.ex` — new fields (base_url, provider_type)
- `lib/app/providers.ex` — remove LLMDB/ValidProviders, add model listing
- `lib/app/agents/runner.ex` — rewrite to use Alloy.run/stream
- `lib/app/agents/tools.ex` — rewrite tool resolution to Alloy tools
- `lib/app/agents/agent.ex` — model format change
- `lib/app/chat/orchestrator.ex` — update runner calls, tool building
- `lib/app/chat/stream_worker.ex` — adapt to Alloy events
- `lib/app/chat/compaction.ex` — simplify, delegate to Alloy
- `lib/app/chat/context_builder.ex` — simplify to thin adapter
- `lib/app_web/live/agent_live/form_component.ex` — model selection UI
- `lib/app_web/live/provider_live/form_component.ex` — base_url, provider_type
- `lib/app_web/live/chat_live/show.ex` — adapt to new result format (if needed)
- All test stubs in `test/support/stubs/`

### Deleted files:
- `lib/app/agents/runner/doom_loop.ex` — replaced by `max_turns`

---

## Migration Order
1. Phase 1 (deps + schema) — foundation
2. Phase 2 (tools) — can be tested in isolation
3. Phase 3 (runner) — core swap, depends on 1+2
4. Phase 4 (context/compaction) — simplification, depends on 3
5. Phase 5 (orchestrator/streaming) — integration, depends on 3+4
6. Phase 6 (model selection UI) — UX, depends on 1
7. Phase 7 (cleanup/testing) — final pass
