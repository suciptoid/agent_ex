# LLM Context Compaction and Checkpoints

## Problem

- Production requests are overflowing the model context window (`167452` requested vs `131072` allowed).
- The current chat pipeline rebuilds prompt context from the full stored transcript with no token budget, no pruning, no compaction checkpoints, and no retry path after overflow.
- `App.Agents.Tools.execute_all/3` feeds full tool outputs straight back into the next LLM call.
- `App.Chat.list_messages/1` returns the full ordered transcript, while `App.Agents.Runner.expand_history_message/1` also expands assistant tool-call turns from nested tool rows / legacy metadata. That likely replays some tool history more than once.

## External reference patterns

### `openai/codex`

- Uses explicit history compaction with both local and remote paths.
- Local compaction (`codex-rs/core/src/compact.rs`) summarizes history and keeps a bounded slice of recent user messages.
- Remote compaction (`codex-rs/core/src/compact_remote.rs`) trims older Codex-generated items until the request fits, then replaces history with a compacted transcript.
- Keeps persistent rollout data for replay/resume instead of mutating raw history in place.

### `anomalyco/opencode`

- Uses `SessionCompaction` in `packages/opencode/src/session/compaction.ts`.
- Auto-compaction is driven by overflow detection plus a reserved token buffer.
- Old completed tool outputs can be pruned while preserving the fact that the tool ran; compacted outputs are replaced with a placeholder in model-visible context.
- Stores compaction summaries as part of session state, effectively acting as checkpoints.

### `badlogic/pi-mono`

- Separates full append-only history from compacted working context.
- Auto-compaction is driven by threshold/overflow in `packages/coding-agent/src/core/agent-session.ts`.
- `packages/coding-agent/src/core/compaction/compaction.ts` keeps a recent raw tail, summarizes older history, and truncates tool results for summarization.
- `log.jsonl` remains the source of truth, while compacted entries act like checkpoints for future turns.

## Current app findings

- `App.Chat.Orchestrator.send_message/3` and `stream_message/3` call `Chat.list_messages/1` and pass the whole room history into the runner.
- `App.Agents.Runner.build_context/3` prepends the system prompt and turns every stored message into `ReqLLM.Context` items with no budget enforcement.
- Tool outputs are stored in full and replayed in full.
- The app already preserves a durable raw transcript, so compaction should be implemented as a derived context layer, not by deleting or rewriting `chat_messages`.
- The current `req_llm` dependency tree does not expose an obvious documented context-compression helper to build around, so the plan assumes an app-owned compaction layer first.

## Proposed implementation

### 1. Normalize prompt history before any compaction work

- Introduce a dedicated context builder (`App.Chat.ContextBuilder` or `App.Agents.ContextBuilder`).
- Build one canonical transcript view from persisted message order.
- Stop double-expanding tool turns when the ordered transcript already contains persisted tool rows.
- Keep multi-agent prompts, delegated-agent messages, and internal tool behavior intact.

### 2. Add model budget policy

- Add a small policy module/config for:
  - context window
  - reserved output tokens
  - auto-compaction threshold
  - recent raw tail budget
  - tool output preview/truncation limit
- Use provider/model-specific values where known, with a conservative heuristic fallback.
- Record estimated input tokens during context building for logs and checkpoint decisions.

### 3. Persist compaction checkpoints inside `chat_messages`

- Extend `chat_messages.role` to support `"checkpoint"`.
- Store each compaction summary as a special checkpoint message in the same append-only message ledger.
- Recommended checkpoint message shape:
  - `role: "checkpoint"`
  - `position` in the room timeline
  - `content` containing the summary
  - `metadata["up_to_position"]`
  - `metadata["raw_tail_start_position"]`
  - `metadata["estimated_tokens_before"]`
  - `metadata["estimated_tokens_after"]`
  - `metadata["checkpoint_version"]`
- Checkpoint rows must not render as normal transcript messages and must not be replayed as ordinary user/assistant turns; the context builder consumes them specially as summaries of earlier history.

### 4. Prune old tool outputs in prompt space only

- For older tool rows outside the recent raw tail:
  - replace full content with a placeholder such as `[Older tool result omitted from prompt; stored in transcript]`
  - keep tool name / tool_call_id / status
  - optionally keep a short preview for non-noisy tools
- Exclude internal, non-user-facing tool turns like `update_chatroom_title` from future prompts unless they affect visible chat state.
- Never delete stored tool output from the database.

### 5. Add auto-compaction service

- Add `App.Chat.Compaction` to summarize older conversation prefixes into checkpoint messages.
- Keep a recent raw tail verbatim and summarize only the older prefix.
- Reuse the active agent/provider/model first to avoid introducing new required configuration.
- Make the summary prompt preserve:
  - user goal
  - important instructions
  - relevant discoveries
  - completed work
  - pending next steps
  - notable files/tools/entities referenced in the chat

### 6. Wire compaction into both sync and streaming paths

- Before every `Runner.run/3` and `run_streaming/4`:
  - build canonical transcript
  - estimate tokens
  - prune old tool outputs if needed
  - select latest checkpoint message + recent raw tail
  - auto-compact if still above threshold
- Ensure the same builder is used for:
  - normal chat responses
  - streaming responses
  - delegated `ask_agent` runs

### 7. Add overflow fallback + retry

- Catch context-window API errors from `ReqLLM.stream_text/3`.
- On first overflow:
  - force pruning / compaction
  - rebuild with a tighter reserve
  - retry once
- If retry still overflows, persist a structured error explaining that the thread needs manual reduction.

### 8. Cover with tests and observability

- Add tests for:
  - canonical transcript building without duplicate tool replay
  - checkpoint-role messages being excluded from visible transcript replay
  - pruning old tool outputs
  - checkpoint selection
  - auto-compaction threshold behavior
  - overflow retry path
  - sync + streaming + delegated-agent parity
- Add logs/telemetry for:
  - estimated input tokens
  - selected checkpoint
  - pruned tool bytes/count
  - compaction runs
  - overflow retries

## Implementation todos

1. `fix-history-replay`: replace ad hoc history expansion with a canonical, non-duplicated transcript builder.
2. `add-context-budget-policy`: define context window/reserve/pruning settings and token estimation helpers.
3. `add-checkpoint-schema`: extend `chat_messages` with a checkpoint role and add the related context functions.
4. `build-context-builder`: assemble checkpoint + raw tail + prompt pruning into one request builder.
5. `add-tool-output-pruning`: replace old tool payloads with placeholders/truncated previews in prompt space.
6. `add-auto-compaction`: summarize old prefixes into checkpoints when thresholds are exceeded.
7. `add-overflow-retry`: retry once after forced compaction/pruning on provider overflow errors.
8. `wire-all-run-paths`: use the new builder in sync, streaming, and delegated-agent flows.
9. `add-tests-and-telemetry`: cover the new flows and expose enough logging to debug future overflows.

## Notes

- Recommended strategy: mirror Codex/OpenCode/Pi-mono by separating **full transcript storage** from **compacted working context**, but keep both inside the same `chat_messages` ledger via a special checkpoint role.
- Do not mutate or destroy old `chat_messages`; append checkpoint messages plus prompt-time pruning instead.
- Fixing duplicate history replay should happen before checkpointing, because otherwise token estimates and compaction decisions will be wrong.
- The `ReqLLM` error mentions a context-compression plugin, but the current dependency tree does not provide a clear app-facing integration point in this repo. Treat any library plugin as optional follow-up, not as the primary plan.

## Follow-up after first implementation

1. Use the provider-reported context window from overflow errors to tighten the retry budget when the static model policy is too optimistic.
2. Persist a checkpoint even when forced compaction still cannot fit the next request, so the room has a durable summary for the next turn.
3. Add Telegram `/new` to rotate a gateway channel onto a fresh chat room and reset context without losing prior transcript history.
4. Extend sidebar chat-room data/rendering so gateway-linked rooms show the gateway icon and expose a hover delete affordance.
5. Cover the new overflow fallback, Telegram reset, sidebar deletion, and linked-room rendering with focused tests.
