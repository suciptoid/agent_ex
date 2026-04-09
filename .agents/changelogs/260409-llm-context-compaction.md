- Researched context-window handling patterns in `openai/codex`, `anomalyco/opencode`, and `badlogic/pi-mono`, focusing on auto-compaction, old tool-result pruning, checkpointing, and overflow recovery.
- Inspected this app's chat pipeline (`App.Chat.Orchestrator`, `App.Agents.Runner`, `App.Chat.StreamWorker`, `App.Agents.Tools`) and identified the current overflow shape: full-history replay, full tool-output replay, no budget/checkpoint layer, and likely duplicate tool-turn expansion during prompt construction.
- Added implementation plans to:
  - `.agents/plans/260409-llm-context-compaction.md`
  - `/Users/sucipto/.copilot/session-state/16d9aa58-3bbd-4be3-9943-02e476ff1d95/plan.md`
- Updated the plan after user feedback to store compaction summaries in `chat_messages` as a special `role: "checkpoint"` entry instead of adding a separate checkpoint table.

By: gpt-5.4 on GitHub Copilot

- Replaced controller-driven sidebar chat deletion with a LiveView-native path by attaching a shared `delete-chat-room` event hook in `AppWeb.UserAuth.on_mount(:require_authenticated)`, so authenticated LiveViews handle sidebar deletes inside the LiveView lifecycle.
- Removed the dedicated chat-room delete controller/route and updated the shared sidebar delete affordance to emit a normal `phx-click` event instead of an HTTP delete link.
- Updated `App.Chat.delete_chat_room/2` to cancel active room streams before deleting the room so background stream workers do not keep writing into a removed chat room.
- Added LiveView coverage for deleting the current room from `ChatLive.Show` and deleting a room from the dashboard sidebar while keeping sidebar/dashboard state in sync.
- Re-ran `mix precommit`; the only remaining failure is still the pre-existing unrelated `AppWeb.GatewayLiveTest` sidebar selector assertion.

By: gpt-5.4 on GitHub Copilot

- Hardened overflow recovery so forced retries reuse the provider-reported context-window limit, compact older history more aggressively when needed, and still persist a checkpoint summary even when the room cannot be recovered within one retry.
- Added a deterministic local checkpoint-summary fallback in `App.Chat.Compaction` so checkpoint persistence does not depend on a second successful LLM call.
- Extended gateway channel handling with chat-room rotation support and Telegram `/new`, so a gateway channel can start a fresh room without losing prior transcript history.
- Updated `Gateways.find_or_create_channel/2` to heal channels whose linked chat room was deleted by attaching a fresh chat room automatically on the next inbound message.
- Extended sidebar chat-room data/rendering with `gateway_linked` state, a gateway icon for linked rooms, and a hover-only delete control for chat-room history items.
- Added `AppWeb.ChatRoomController.delete/2` and routed `DELETE /chat/:id` through the existing authenticated `:browser + :require_authenticated_user + :active_organization_required` controller scope so deletion uses the same `current_scope` and organization guardrails as the chat LiveViews while remaining callable from the shared sidebar layout.
- Added follow-up tests for gateway-linked sidebar state, persistent checkpoints after unrecoverable overflow, Telegram `/new`, sidebar controls, and chat-room deletion redirects.
- Ran `mix precommit`; the only remaining failure is still the pre-existing unrelated `AppWeb.GatewayLiveTest` sidebar selector assertion.

By: gpt-5.4 on GitHub Copilot

- Implemented `App.Chat.ContextBuilder` to build a canonical prompt transcript, stop duplicate tool-turn replay, estimate token usage, apply model/context budget policy, reuse the latest checkpoint, and prune older tool outputs in prompt space.
- Implemented `App.Chat.Compaction` and wired forced/threshold-based checkpoint generation into the existing `chat_messages` ledger via `role: "checkpoint"` messages with summary metadata (`up_to_position`, raw-tail boundary, token estimates, version).
- Updated `App.Agents.Runner` to consume the canonical context builder and treat checkpoint entries as system-style context rather than replaying them as normal transcript rows.
- Updated `App.Chat.Orchestrator` to prepare context uniformly for sync, streaming, and delegated runs, retry once on provider context-window errors with forced compaction, and emit telemetry for prepared prompts, checkpoint creation, and overflow retries.
- Updated chat UI handling to keep checkpoint messages hidden from the visible transcript.
- Added focused coverage for canonical transcript behavior, budget-policy override precedence, overflow retry with checkpoint insertion, streaming retry behavior, and hidden checkpoint rendering, plus test stubs for compaction and overflow-aware runner behavior.
- Ran `mix precommit`; the only remaining failure is the pre-existing unrelated `AppWeb.GatewayLiveTest` sidebar selector assertion.

By: gpt-5.4 on GitHub Copilot
