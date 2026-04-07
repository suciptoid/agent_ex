Problem: replace the runner's fixed tool-iteration cap with a doom-loop detector based on repeated identical tool calls, and fix the empty flash shown when the first message creates and redirects into a chat room.

Approach:
- Mirror OpenCode's doom-loop idea in `App.Agents.Runner`: inspect recent tool-call turns, detect consecutive repeats of the same tool name plus normalized arguments, and stop with an explicit error instead of relying on a blanket iteration counter.
- Remove the nil flash assignment in the new-chat redirect flow and add focused regression coverage.
- Validate with targeted tests and `mix precommit`.

Todos:
- Refactor runner loop guard to use repeated-tool-call detection.
- Fix the new-chat redirect flash regression.
- Add focused tests and run validation.

Notes:
- DeepWiki's direct Q&A endpoint for `anomalyco/opencode` was unavailable, but the DeepWiki repository page pointed to `packages/opencode/src/session/processor.ts`, where `DOOM_LOOP_THRESHOLD = 3` and the loop detection logic checks the last N tool parts for identical tool name plus identical serialized input before escalating.
