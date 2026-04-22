# Multi-Agent Roster & Subagent Title

## Changes

### orchestrator.ex - `multi_agent_opts/3`
- Replaced verbose tool descriptions in the extra prompt with bare tool names (`subagent_lists`, `subagent_spawn`, `subagent_wait`)
- Added `## Available Agents` section listing each agent's name, id, and tool names (no descriptions)
- Added `format_agent_list/1` helper to build the agent roster string

### subagent_spawn.ex
- Added optional `title` property to `input_schema`
- When `title` is provided in input, it is passed through to `Chat.create_subagent_chat_room/3` as the child chat room title

### test/app/chat_test.exs
- Updated the "injects only subagent tools" test to reflect the new behavior where agent roster details ARE now included in the prompt
- Renamed test to "injects subagent tools and agent roster with id, name, and tools in the extra prompt"

By: glm-5.1 on OpenCode
