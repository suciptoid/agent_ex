Problem:
- Add typed chat rooms with archive behavior, a full chat list view, and an Oban-backed scheduled task system that stores each run as a task chat room and can notify a linked gateway channel.

Approach:
- Extend `chat_rooms` with a typed enum and context helpers so sidebar visibility, archive/unarchive actions, and gateway rotation all use the same source of truth.
- Add a new `/chat/all` LiveView for broader chat management outside the sidebar.
- Introduce an `App.Tasks` context with a scheduled task schema, task-agent join records, Oban workers, and run helpers that create `:task` chat rooms.
- Add a builtin channel notification tool plus task-level notification target selection so background runs can relay assistant output into an active gateway chat room while still persisting messages locally.

Todos:
- `chatroom-types`: add chat room type enum, migration, sidebar filtering, archive/unarchive helpers, and gateway `/new` archiving.
- `chat-all-page`: add `/chat/all` LiveView with tabs for all, archived, and task chat rooms and row actions.
- `scheduled-tasks`: add scheduled task schema/context, task-agent assignment, repeat/next-run calculation, Oban config, and worker execution.
- `channel-notify-tool`: add channel notification tooling for task runs and relay behavior to active gateway-linked rooms.
- `ui-routes-tests`: wire routes/navigation and cover the new chat/task flows with tests.

Notes:
- Treat the sidebar as a `:general` chat shortcut list; task, gateway, and archived rooms belong in `/chat/all`.
- Preserve current gateway behavior by rotating the channel to a fresh `:gateway` room and marking the old one `:archived`.
- Use the existing authenticated active-organization route scope so chat/task pages keep `current_scope` and org isolation.
