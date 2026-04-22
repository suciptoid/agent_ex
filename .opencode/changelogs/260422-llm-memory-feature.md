# Changelog: LLM Memory Feature

## 2026-04-22

### New Files
- `priv/repo/migrations/20260422044355_create_agent_memories.exs` - Migration for `agent_memories` table with partial unique indexes (per scope), GIN index on tags, and standard lookup indexes
- `lib/app/agents/memory.ex` - `App.Agents.Memory` schema: key, value, tags (string array), scope (org/user/chat), belongs_to agent/org/user/chat_room
- `lib/app/agents/alloy_tools/memory_set.ex` - `AlloyTools.MemorySet` tool: save/update memories with key, value, tags, scope
- `lib/app/agents/alloy_tools/memory_get.ex` - `AlloyTools.MemoryGet` tool: retrieve by key, search by tags, or free-text search
- `lib/app/agents/alloy_tools/memory_update.ex` - `AlloyTools.MemoryUpdate` tool: update existing memory value and/or tags
- `lib/app/agents/memory_middleware.ex` - `App.Agents.MemoryMiddleware` Alloy.Middleware: injects preferences/profile memories into system prompt + appends memory tool usage instructions

### Modified Files
- `lib/app/agents.ex` - Added memory context functions: `set_memory/1`, `get_memory/4`, `get_memories_by_tags/3`, `list_memories_for_prompt/2`, `search_memories/3`, `delete_memory/1`
- `lib/app/agents/tools.ex` - `resolve/2` now always appends memory tools (MemorySet, MemoryGet, MemoryUpdate) as internal tools
- `lib/app/agents/runner.ex` - Added `MemoryMiddleware` to middleware stack, passes `agent_id`/`user_id`/`chat_room_id` in alloy context
- `lib/app/agents/agent.ex` - Added `has_many :memories` association
- `test/app/agents/tools_test.exs` - Updated 4 tests to handle memory tools being always present in resolve output

### Architecture
- **Active recall**: `MemoryMiddleware` (`:before_completion`) injects memories tagged `preferences`/`profile` into system prompt
- **Active save prompt**: Middleware appends memory tool instructions, encouraging LLM to call `memory_set`/`memory_update` when it learns important info
- **Passive tools**: `memory_set`, `memory_get`, `memory_update` are always-available internal Alloy tools (not in agent tool checkboxes)
- **Scopes**: `org` (shared), `user` (per-user), `chat` (per-chat+user) with partial unique indexes
- **Tags**: String array with GIN index; standard tags: preferences, profile, fact, instruction, note

By: glm-5.1 on OpenCode
