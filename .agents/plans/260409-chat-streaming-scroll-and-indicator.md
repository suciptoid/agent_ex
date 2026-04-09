# Chat streaming scroll and indicator fixes

## Problem

The `/chat/:id` transcript still has three UX issues during streaming:

1. Manual upward scrolling can still fight with sticky autoscroll while tokens keep arriving.
2. The live streaming pill renders before assistant content, so partial text appears to start above the status indicator instead of ending with it.
3. Delegated placeholders can look like they are already streaming while the current agent is still in a tool phase and the delegated agent has not emitted any thinking/text yet.

## Approach

- Tighten the `.ChatMessages` hook so any real upward user scroll disables sticky autoscroll until the viewport returns to the bottom or the jump-to-bottom control is used.
- Reorder the assistant body in `show.html.heex` so thinking/tool blocks stay above content and the live status indicator sits underneath the latest rendered content.
- Replace the single pulse dot with a sequential three-dot loader using Tailwind utility classes and staggered animation delays.
- Gate delegated streaming indicators on actual live stream activity instead of placeholder existence alone, then cover that behavior with a focused LiveView test.

## Validation

- Run `mix test test/app_web/live/chat_live_test.exs`
- Run `mix precommit`
