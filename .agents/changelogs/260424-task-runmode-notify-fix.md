- Fixed scheduled task run delivery so task executions now auto-relay final assistant output into the configured notification chat room, which then relays to the linked gateway channel (Telegram).
- Added duplicate-protection: if the run already delivered via `channel_send_message` tool, automatic relay is skipped.
- Added first-save bootstrap for repeat tasks (`last_run_at == nil`): on create/edit save, repeat tasks are scheduled to run immediately and their next run is generated.
- Updated task scheduling model flow with explicit `run_mode` (`once` / `repeat`) mapped to existing `repeat` storage.
- Relaxed next-run validation for repeat mode so it no longer requires `next_run_input`.
- Extended repeat interval units to include `minute`.
- Reworked Task editor UI:
  - run mode section is now directly below task title
  - repeat scheduling uses `cron` or `every + value + unit`
  - prompt remains textarea
  - removed old repeat checkbox block
- Implemented browser-timezone datetime UX via new LiveView hook:
  - visible local `datetime-local` input for once mode
  - hidden UTC field auto-synced before validate/submit
  - browser timezone captured in hidden field
- Updated tests:
  - task context tests for repeat bootstrap and relay-to-telegram behavior
  - LiveView task form tests for new `run_mode` params and UI selection assertions
- Validation: `mix precommit` passes.

By: gpt-5.4 on OpenCode

- Fixed gateway `/new` channel-rotation regression for task notifications:
  - During `Gateways.reset_channel_chat_room/1`, scheduled tasks that referenced the previous notification room are now retargeted to the new active channel room.
  - Added stale recovery on rotation: tasks pointing to unlinked archived/gateway rooms with the same channel title are also retargeted.
- Added regression coverage in Telegram handler `/new` rotation test to assert the scheduled task `notification_chat_room_id` is moved to the fresh channel room.
- Validation: `mix format && mix precommit` passes.

By: gpt-5.4 on OpenCode
