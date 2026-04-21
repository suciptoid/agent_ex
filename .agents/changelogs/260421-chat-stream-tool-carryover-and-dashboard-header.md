## Chat stream carryover and dashboard header

- Cleared transient tool-response state when the stream worker hands off from a tool-call assistant row to the follow-up assistant row, so the resumed message starts from a clean transcript state.
- Added explicit `:stream_complete` and `:stream_error` handling in `AppWeb.ChatLive.Show` to refresh the transcript and reset main-stream assigns as soon as a main response finishes.
- Added a sequential LiveView regression that runs two tool-assisted assistant turns back to back and asserts the later follow-up row does not inherit the prior tool accordion.
- Reworked the dashboard header in `AppWeb.DashboardLive` into a calmer split layout with tighter grouping, clearer hierarchy, and a less heavy hero treatment while preserving the existing IDs and primary action flow.
- Verified with focused chat/dashboard tests and `mix precommit`.

By: gpt-5.4 on Github Copilot
