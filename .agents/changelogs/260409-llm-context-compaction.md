- Researched context-window handling patterns in `openai/codex`, `anomalyco/opencode`, and `badlogic/pi-mono`, focusing on auto-compaction, old tool-result pruning, checkpointing, and overflow recovery.
- Inspected this app's chat pipeline (`App.Chat.Orchestrator`, `App.Agents.Runner`, `App.Chat.StreamWorker`, `App.Agents.Tools`) and identified the current overflow shape: full-history replay, full tool-output replay, no budget/checkpoint layer, and likely duplicate tool-turn expansion during prompt construction.
- Added implementation plans to:
  - `.agents/plans/260409-llm-context-compaction.md`
  - `/Users/sucipto/.copilot/session-state/16d9aa58-3bbd-4be3-9943-02e476ff1d95/plan.md`
- Updated the plan after user feedback to store compaction summaries in `chat_messages` as a special `role: "checkpoint"` entry instead of adding a separate checkpoint table.

By: gpt-5.4 on GitHub Copilot

- Implemented `App.Chat.ContextBuilder` to build a canonical prompt transcript, stop duplicate tool-turn replay, estimate token usage, apply model/context budget policy, reuse the latest checkpoint, and prune older tool outputs in prompt space.
- Implemented `App.Chat.Compaction` and wired forced/threshold-based checkpoint generation into the existing `chat_messages` ledger via `role: "checkpoint"` messages with summary metadata (`up_to_position`, raw-tail boundary, token estimates, version).
- Updated `App.Agents.Runner` to consume the canonical context builder and treat checkpoint entries as system-style context rather than replaying them as normal transcript rows.
- Updated `App.Chat.Orchestrator` to prepare context uniformly for sync, streaming, and delegated runs, retry once on provider context-window errors with forced compaction, and emit telemetry for prepared prompts, checkpoint creation, and overflow retries.
- Updated chat UI handling to keep checkpoint messages hidden from the visible transcript.
- Added focused coverage for canonical transcript behavior, budget-policy override precedence, overflow retry with checkpoint insertion, streaming retry behavior, and hidden checkpoint rendering, plus test stubs for compaction and overflow-aware runner behavior.
- Ran `mix precommit`; the only remaining failure is the pre-existing unrelated `AppWeb.GatewayLiveTest` sidebar selector assertion.

By: gpt-5.4 on GitHub Copilot
