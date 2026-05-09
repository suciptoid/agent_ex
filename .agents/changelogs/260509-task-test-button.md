# Task Test Run Button

## Changes

### `lib/app/tasks.ex`
- Added `enqueue_test_run/2` public function that immediately enqueues an Oban `TaskRunWorker` job for a given task, bypassing the schedule. Uses `get_task/2` for scope authorization.

### `lib/app_web/live/task_live/index.ex`
- Added `test_task_id` assign (nil by default) to track which task is being tested
- Added `confirm-test-task` event handler — sets `test_task_id` to open the dialog
- Added `cancel-test-task` event handler — clears `test_task_id` to close the dialog
- Added `test-task` event handler — calls `Tasks.enqueue_test_run`, shows flash on success/failure, refreshes task list
- Added **Test** button (with `hero-play` icon) before the Edit button on each task row
- Added **PUI Dialog** (`<.dialog>`) with server-controlled `show={@test_task_id != nil}` for confirmation, including Cancel and "Run now" buttons

## Memory Issue Investigation (Findings Only)

The root cause of "scheduled task chatrooms have no memory" was traced:

1. **`Tasks.run_task_prompt/2`** passes `alloy_context` without `user_id`
2. **`Runner.build_alloy_context/2`** sets `user_id` from opts (`nil` for tasks)
3. **`MemoryMiddleware`** → `list_user_profile_memories_for_prompt/1` returns `[]` because `user_id` is missing
4. Org-scoped memories are injected as **keys only** (not values), requiring the agent to actively call `memory_get`
5. User-scoped memories are completely invisible to scheduled tasks

No fix was applied for the memory issue — only the test button was implemented.

By: gpt-5.4 on Pi Coding Agent
