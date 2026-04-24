Problem:
- Gateway `/new` chat rotation should create a new room linked to the previous archived room as parent.
- Sidebar and chat management still rely on `general` room type; requested rename to `chat` and include gateway rooms in sidebar.
- `/chat/all` needs dedicated Gateway tab.
- Memory retrieval and prompt-injection need improvements: blank-scope queries should not silently fail, user/agent preferences should be injected, and org memory should inject keys only.

Approach:
- Refactor chat room type usage from `:general` -> `:chat` across schema, context logic, UI labels, and tests.
- Add DB migration to convert existing `chat_rooms.type` values from `general` to `chat`.
- Update gateway room rotation flow to create new room with `parent_id` pointing at prior room.
- Expand sidebar filters to include gateway rooms.
- Add Gateway tab to `/chat/all` filtering and counts.
- Improve memory middleware injection strategy (user profile/preferences + agent preferences full values, org memory keys-only), and make `memory_get` scope-only queries useful by listing memories.

Steps:
1) Chat type refactor + migration + sidebar/all tabs.
2) Gateway `/new` parent linkage.
3) Memory tool behavior and middleware prompt-injection updates.
4) Update tests and run `mix precommit`.
