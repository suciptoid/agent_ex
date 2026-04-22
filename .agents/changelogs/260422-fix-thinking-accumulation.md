## 260422 Fix thinking block accumulation

### Changes
- **`lib/app/agents/runner.ex`**: Modified `extract_thinking/1` to only extract thinking from the last assistant message instead of concatenating thinking from all assistant messages in the Alloy result.

### Files changed
- `lib/app/agents/runner.ex` (lines 556-574 → rewritten)

By: GLM-5.1 on OpenCode
