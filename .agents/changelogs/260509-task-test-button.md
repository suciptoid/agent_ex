# Task Test Run Button + Memory Fix for Scheduled Tasks

## Changes

### `lib/app/tasks.ex`
- Added `enqueue_test_run/2` public function that immediately enqueues an Oban `TaskRunWorker` job for a given task, bypassing the schedule. Uses `get_task/2` for scope authorization.
- **Memory fix**: Modified `run_task_prompt/2` to resolve the notification chat room's linked gateway channel. If the channel is a private Telegram DM (`metadata["chat_type"] == "private"`), the mapped app `user_id` is resolved via `Gateways.mapped_user_id_for_channel/1` and injected into the `alloy_context`. This allows `MemoryMiddleware` to load user-scoped memories for the task agent.
- Added `resolve_notification_user_id/1` — looks up the channel by notification chat room ID, checks if it's a private chat, and returns the mapped user_id.
- Added `maybe_put_alloy_user_id/2` — conditionally adds `user_id` to the alloy context map.

### `lib/app_web/live/task_live/index.ex`
- Added `test_task_id` assign (nil by default) to track which task is being tested
- Added `confirm-test-task` event handler — sets `test_task_id` to open the dialog
- Added `cancel-test-task` event handler — clears `test_task_id` to close the dialog
- Added `test-task` event handler — calls `Tasks.enqueue_test_run`, shows flash on success/failure, refreshes task list
- Added **Test** button (with `hero-play` icon) before the Edit button on each task row
- Added **PUI Dialog** (`<.dialog>`) with server-controlled `show={@test_task_id != nil}` for confirmation, including Cancel and "Run now" buttons

## Memory Issue Fix

The root cause was that `Tasks.run_task_prompt/2` passed no `user_id` in the `alloy_context`, so `MemoryMiddleware` could not find user-scoped memories.

**Fix**: When the scheduled task has a `notification_chat_room` linked to a **private** gateway channel (e.g. Telegram DM), the mapped app `user_id` from that channel is now passed as `user_id` in the alloy context. This enables:
1. `MemoryMiddleware` → `list_user_profile_memories_for_prompt` to inject user memories into the system prompt
2. `memory_get` tool to access user-scoped memories when the agent calls it

For tasks without a private notification channel (group chats, no notification room, or unmapped users), the behavior remains unchanged — only org-scoped and agent-scoped memories are available.

By: gpt-5.4 on Pi Coding Agent
