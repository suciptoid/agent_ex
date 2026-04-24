Problem:
- Scheduled task runs are creating task chat rooms but not reliably delivering generated output into the linked gateway chat room / Telegram channel.
- Task editor UX still uses old repeat toggle + UTC datetime flow, and does not match requested run mode behavior.

Approach:
- Update task run pipeline to auto-relay final assistant output to configured notification chat room (and downstream gateway), with duplicate protection when `channel_send_message` already executed.
- Introduce explicit run mode (`once`/`repeat`) in task form/changeset flow while preserving existing DB schema (`repeat` boolean + schedule fields).
- Switch scheduled datetime input to browser-local UX with client-side conversion to UTC before submission.
- Add repeat bootstrap behavior on save for never-run tasks: schedule immediate run and compute/store next run.

Implementation steps:
- Patch `App.Tasks` run flow, save flow, and scheduling helpers.
- Patch `App.Tasks.Task` validation/normalization to support run mode mapping.
- Extend `App.Tasks.Schedule` to include minute interval unit.
- Update Task LiveView form UI structure and params.
- Add JS hook in `assets/js/app.js` for local datetime <-> UTC input sync.
- Update task tests/live tests and run `mix precommit`.
