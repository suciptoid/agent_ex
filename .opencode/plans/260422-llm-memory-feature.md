# Plan: LLM "Memory" Feature

## Overview

Add persistent memory for agents with scoped storage, tag-based retrieval, active recall/injection, and passive save tools. Memories are stored in `agent_memories`, injected into the system prompt by an `Alloy.Middleware`, and the LLM can passively save/recall via internal tools.

---

## Architecture

### Scope Model

| Scope    | Unique constraint fields                         | Notes                                    |
|----------|--------------------------------------------------|------------------------------------------|
| `org`    | `(agent_id, key)` where user_id & chat_room_id are NULL | Shared across org for this agent        |
| `user`   | `(agent_id, key, user_id)` where chat_room_id is NULL   | Per-user memories for this agent        |
| `chat`   | `(agent_id, key, user_id, chat_room_id)`               | Per-chat, per-user memories for agent   |

### Tag System

Tags are stored as JSONB array. Standard tags:
- `preferences` - user preferences (injected into system prompt)
- `profile` - user profile info (injected into system prompt)
- `fact` - general facts
- `instruction` - behavioral instructions
- `note` - freeform notes

### Active vs Passive Memory

- **Active (middleware)**: `MemoryMiddleware` injects `preferences`/`profile` tagged memories into system prompt before each completion. Also injects prompt instructions telling the LLM to call `memory_set`/`memory_update` when it discovers important information.
- **Passive (tools)**: LLM can call `memory_set`, `memory_get`, `memory_update` tools anytime. These are always-enabled internal tools (not shown in agent tool checkboxes UI).

---

## Files to Create/Modify

### 1. Migration: `priv/repo/migrations/TIMESTAMP_create_agent_memories.exs`

```
create table(:agent_memories, primary_key: false)
  id          :binary_id, PK
  key         :string, null: false
  value       :text, null: false
  tags        :map (jsonb), default: []
  scope       :string, null: false
  agent_id    :binary_id, FK -> agents, null: false
  organization_id :binary_id, FK -> organizations, null: false
  user_id     :binary_id, FK -> users, nullable
  chat_room_id :binary_id, FK -> chat_rooms, nullable
  timestamps(type: :utc_datetime_usec)

Indexes:
  - unique partial: (agent_id, key, scope, COALESCE(user_id, ...), COALESCE(chat_room_id, ...))
  - GIN on :tags (for @> containment queries)
  - :agent_id, :scope
  - :agent_id, :key
  - :organization_id
```

### 2. Schema: `lib/app/agents/memory.ex`

Module `App.Agents.Memory`:
- Ecto schema with fields above
- `belongs_to :agent`, `belongs_to :organization`, `belongs_to :user`, `belongs_to :chat_room`
- Changeset: validate required `[:key, :value, :scope, :agent_id, :organization_id]`, validate scope inclusion `~w(org user chat)`, validate tags is list, normalize tags

### 3. Context Functions: modify `lib/app/agents.ex`

Add to `App.Agents` context:
- `set_memory(attrs)` - Upsert memory (create or update by unique key)
- `get_memory(scope, agent_id, key, opts)` - Get single memory by key+scope
- `get_memories_by_tags(agent_id, tags, opts)` - Query memories containing any of the given tags
- `list_memories_for_prompt(agent_id, opts)` - Fetch memories tagged `preferences` or `profile` for system prompt injection
- `delete_memory/1`

`opts` carries `:organization_id`, `:user_id`, `:chat_room_id` for scope filtering.

### 4. Alloy Tool: `lib/app/agents/alloy_tools/memory_set.ex`

Module `App.Agents.AlloyTools.MemorySet`:
- `@behaviour Alloy.Tool`
- `name/0` -> `"memory_set"`
- `description/0` -> "Save a memory for later recall."
- `input_schema/0` -> `{key, value, tags: array of strings, scope: enum(org/user/chat)}`
- `execute/2` -> Extracts scope info from context, calls `App.Agents.set_memory/1`

### 5. Alloy Tool: `lib/app/agents/alloy_tools/memory_get.ex`

Module `App.Agents.AlloyTools.MemoryGet`:
- `name/0` -> `"memory_get"`
- `input_schema/0` -> `{key (optional), tags: array of strings (optional), scope (optional)}`
- `execute/2` -> Calls `App.Agents.get_memory` or `App.Agents.get_memories_by_tags`

### 6. Alloy Tool: `lib/app/agents/alloy_tools/memory_update.ex`

Module `App.Agents.AlloyTools.MemoryUpdate`:
- `name/0` -> `"memory_update"`
- `input_schema/0` -> `{key, value (optional), tags: array of strings (optional), scope (optional)}`
- `execute/2` -> Gets existing memory then updates

### 7. Memory Middleware: `lib/app/agents/memory_middleware.ex`

Module `App.Agents.MemoryMiddleware` implementing `Alloy.Middleware`:

**`call(:before_completion, state)`**:
1. Get `agent_id`, `organization_id`, `user_id`, `chat_room_id` from `state.config.context`
2. Fetch memories tagged `preferences` or `profile` via `App.Agents.list_memories_for_prompt/2`
3. If memories found, append formatted block to the system prompt (modify state messages or system prompt)
4. Append memory tool instruction block to system prompt

Memory instruction block (injected into system prompt):
```
## Memory
You have internal tools to persist and recall information across conversations:
- memory_set: Save facts, preferences, or notes about the user
- memory_get: Retrieve stored memories
- memory_update: Update existing memories
Proactively use these tools when the user shares preferences, personal details, or important context worth remembering.
```

**`call(_hook, state)`**: Pass through for all other hooks.

### 8. Modify `lib/app/agents/tools.ex`

- Add `resolve_memory_tools/0` returning `[AlloyTools.MemorySet, AlloyTools.MemoryGet, AlloyTools.MemoryUpdate]`
- Modify `resolve/2` to always append memory tools (not gated by `agent.tools`)

### 9. Modify `lib/app/agents/runner.ex`

- In `stream_middleware/1`, add `App.Agents.MemoryMiddleware` to the middleware list (before StreamMiddleware)
- In `build_alloy_context/2`, pass `agent_id` into the context map for memory middleware

### 10. Modify `lib/app/agents/agent.ex`

- Add `has_many :memories, App.Agents.Memory` association

---

## Execution Order

1. Generate migration via `mix ecto.gen.migration create_agent_memories`
2. Write migration with table + indexes
3. Create `lib/app/agents/memory.ex` schema
4. Add memory functions to `lib/app/agents.ex` context
5. Create `lib/app/agents/alloy_tools/memory_set.ex`
6. Create `lib/app/agents/alloy_tools/memory_get.ex`
7. Create `lib/app/agents/alloy_tools/memory_update.ex`
8. Create `lib/app/agents/memory_middleware.ex`
9. Modify `lib/app/agents/tools.ex` to always include memory tools
10. Modify `lib/app/agents/runner.ex` to wire middleware + context
11. Modify `lib/app/agents/agent.ex` to add has_many
12. Run `mix ecto.migrate` and `mix precommit`
