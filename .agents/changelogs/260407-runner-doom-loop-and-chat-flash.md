Implemented an OpenCode-style doom-loop detector for `App.Agents.Runner` by replacing the fixed `@max_tool_iterations` stop with repeated-tool-call detection based on consecutive identical tool name + arguments.

Added `App.Agents.Runner.DoomLoop` with focused tests covering third-repeat detection, differing arguments, and repeated calls within the same response batch.

Fixed the new-chat redirect regression by removing the `put_flash(:info, nil)` call before navigating into the newly created chat room, and updated the LiveView test to assert the redirect carries no flash payload.

Validation:
- `mix test test/app/agents/runner_doom_loop_test.exs test/app_web/live/chat_live_test.exs` passed.
- `mix precommit` still reports the existing unrelated baseline failures in `AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, and `App.UsersTest`.
