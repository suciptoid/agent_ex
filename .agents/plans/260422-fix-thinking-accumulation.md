# Fix: Thinking block accumulation across tool-call turns

## Problem
The last agent message's thinking block includes ALL previous tool-call turns' thinking concatenated together, instead of only its own thinking.

## Root Cause
`extract_thinking/1` in `lib/app/agents/runner.ex` extracted thinking blocks from **ALL** assistant messages in the Alloy result, joining them with `Enum.join("")`. This accumulated thinking then flowed into the final message's metadata via `response_metadata/1` in the orchestrator and `persist_success/6` in the stream worker.

## Fix
Modified `extract_thinking/1` to only extract thinking from the **last** assistant message in the Alloy result. Intermediate tool-call turns already have their own thinking stored correctly via `split_assistant_turn` (streaming) and `persist_tool_call_turns` (sync).
