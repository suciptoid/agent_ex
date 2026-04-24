- Added typed chat rooms (`:general`, `:archived`, `:task`, `:gateway`) with sidebar filtering limited to general chats, archive/unarchive helpers, and gateway `/new` rotation that archives the previous room and creates a fresh gateway room.
- Added `/chat/all` inside the authenticated active-organization LiveView scope so archived, task, and gateway rooms remain discoverable with delete/archive/unarchive actions outside the sidebar.
- Installed and configured Oban with the `oban_jobs` migration, a cron-driven schedule scanner worker, scheduled task schemas/context, task-agent assignments, repeat scheduling (`cron` or `every`), and task-run chat rooms of type `:task`.
- Added the `channel_send_message` Alloy tool plus gateway notification persistence/relay so scheduled task runs can write assistant notifications into the configured active channel chat room.
- Added task management LiveViews (`/tasks`, `/tasks/new`, `/tasks/:id/edit`), sidebar navigation, fixtures, and regression coverage for chat typing, gateway archiving, task scheduling, and the new builtin tool.
- Fixed the task form validation crash by correcting the `Tasks.change_task/3` argument order in `TaskLive.Form`.
- Fixed the task form select wiring to use PUI's `{value, label}` option shape, preserving human-readable labels for main agent / linked channel selects and keeping repeat-mode select values stable during validation.
- Replaced the task form's unstable PUI dropdowns with native selects for main agent, repeat mode, interval unit, and notification chat room; notification chat room options now come directly from gateway-linked rooms instead of summary metadata, and agent memories now honor explicit `org` / `user` / `agent` ownership rules with blank-key lookups rejected early.
- Removed the persisted `scope` field from agent memories, rebuilt memory ownership around nullable `agent_id` / `user_id` / `organization_id`, and added a cleanup migration so existing rows and indexes move off the old schema safely.

By: gpt-5.4 on Github Copilot
