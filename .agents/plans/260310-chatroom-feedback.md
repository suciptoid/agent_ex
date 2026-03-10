# Chatroom Feedback — Detailed Implementation Plan

## Problem Statement
Multiple UX, bug, and feature improvements needed for the chatroom and dashboard layout.

---

## Task Breakdown

### A. Sidebar / Dashboard Layout

**A1. Fix sidebar user menu not clickable**
- Root cause: `<div class="flex flex-col h-full overflow-hidden">` on the inner sidebar div clips the PUI.Dropdown popup
- Fix: Remove `overflow-hidden` from the inner sidebar wrapper, and set `overflow-y-auto` only on the `<nav>` element
- File: `lib/app_web/components/layouts.ex`

**A2. Move Settings & Logout into user menu only (remove from nav)**
- Settings and Logout are already in the `.menu_button` `:items` slot
- Remove the standalone Settings nav link from sidebar `<nav>`
- File: `lib/app_web/components/layouts.ex`

---

### B. Chatroom UX

**B1. Enter to send, Shift+Enter for newline**
- Add a colocated Phoenix LiveView JS hook on the textarea
- Intercept `keydown` event: if `Enter` without `Shift`, prevent default and submit the form
- If `Shift+Enter`, allow default newline behavior
- File: `lib/app_web/live/chat_live/show.html.heex`

**B2. Chat messages as list items (not cards)**
- Redesign the message display to use a simple list-item style
- Each message is a row: avatar/icon + sender + content, like a chat thread (Discord/Slack style)
- Remove the heavy card borders, simplify styling
- File: `lib/app_web/live/chat_live/show.html.heex`

**B3. Tool call response truncation with expand**
- For messages containing tool responses (role: "tool" or metadata.finish_reason: "tool_calls"),
  show only first ~300 chars of content with a "Show more" / "Show less" toggle
- Use a colocated JS hook or Alpine-style data attribute for the toggle
- Files: `lib/app_web/live/chat_live/show.html.heex`, `lib/app_web/live/chat_live/show.ex`

---

### C. LLM / Backend

**C1. Bug fix: tool call content blank**
- Root cause: When LLM returns `finish_reason: "tool_calls"`, the orchestrator tries to save the response as an assistant message but `ReqLLM.Response.text(response)` returns nil → changeset fails on `content: :required`
- Fix: Implement an agentic tool execution loop in the orchestrator:
  1. Call LLM → if `finish_reason: "tool_calls"`, extract tool calls
  2. Execute each tool call via `App.Agents.Tools.execute/2`
  3. Build tool result messages and append to context
  4. Call LLM again with updated context
  5. Repeat up to max_iterations (default 5), then return final response
- Also add `execute/2` function to `App.Agents.Tools`
- Files: `lib/app/chat/orchestrator.ex`, `lib/app/agents/tools.ex`, `lib/app/agents/runner.ex`

**C2. Add logging on LLM requests/responses**
- Add `Logger.debug` calls in:
  - `App.Agents.Runner.run/3`: log model, token counts on response
  - `App.Chat.Orchestrator.send_message/3`: log start/end, errors
  - Tool execution: log tool name, input, result
- Files: `lib/app/agents/runner.ex`, `lib/app/chat/orchestrator.ex`, `lib/app/agents/tools.ex`

**C3. Streaming LLM responses (real-time UI updates)**
- Use `ReqLLM.stream_text/3` which returns `{:ok, %ReqLLM.StreamResponse{}}`
- Architecture:
  1. `handle_event("send")` in LiveView creates user message, inserts a temporary streaming message into stream
  2. Spawns a `Task` that calls a new `Orchestrator.stream_message/4` function with the LiveView pid
  3. The orchestrator builds context and calls `ReqLLM.stream_text/3`
  4. Task iterates `ReqLLM.StreamResponse.tokens(stream_response)` and sends `{:stream_chunk, chunk}` to LV pid
  5. When done, task sends `{:stream_done, %{content: full_text, metadata: ..., agent_id: ...}}`
  6. `handle_info({:stream_chunk, ...}, socket)` updates the streaming_message assign and re-inserts to stream
  7. `handle_info({:stream_done, ...}, socket)` saves final message to DB, replaces temp message
- Files: `lib/app/chat/orchestrator.ex`, `lib/app_web/live/chat_live/show.ex`, `lib/app_web/live/chat_live/show.html.heex`

**C4. Multi-agent system prompt injection + handover tool**
- When a chat room has multiple agents, inject a roster into the commander's system prompt:
  ```
  You are the commander agent. Other agents in this room: [AgentName (id: ...): purpose...]
  To delegate a task to another agent, use the `handover` tool with agent_id and instructions.
  ```
- Add a built-in `handover` tool in `App.Agents.Tools`:
  - Parameters: `agent_id` (string), `instructions` (string)
  - Callback: calls the target agent's `Runner.run/3` with a sub-context and returns the result
- The orchestrator injects the roster and handover tool when the room has multiple agents
- Files: `lib/app/agents/tools.ex`, `lib/app/agents/runner.ex`, `lib/app/chat/orchestrator.ex`

---

## Execution Order

1. A1 + A2 (sidebar fix) — quick win
2. C1 (tool call bug fix) — critical bug
3. C2 (add logging) — quick
4. B1 (enter to send) — UX quick win
5. B2 (list items UI) — UX
6. B3 (tool call truncation) — UX
7. C3 (streaming) — bigger feature
8. C4 (multi-agent handover) — biggest feature
