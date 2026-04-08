# Plan

Problem: builtin/internal tools are not surfaced on `/tools/list`, and there is no agent-assignable tool that can persist new organization tools from an LLM tool call.

Approach:
- add explicit builtin tool metadata so assignable internal tools can be reused by the agent runtime, agent forms, and the tools index
- implement a new builtin `create_tool` that persists a tool with the same fields and validation model used by the `/tools/create` UI flow
- update LiveView and context tests to cover visibility, assignment, and execution

Notes:
- keep `/tools/list`, `/tools/create`, and `/tools/:id/edit` in the existing authenticated `:require_active_organization` live session because tool records remain organization-scoped resources
- do not expose transient chat-only tools like `update_chatroom_title`, `handover`, or `ask_agent` on the tools index
- follow-up: persist default `navigation`, `return_to`, and `display_mode` assigns inside `AppWeb.AgentLive.FormComponent.update/2` so modal edit saves cannot crash when those assigns are omitted by a caller
