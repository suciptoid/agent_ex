## Chat streaming scroll and indicator fixes

- Changed the `/chat/:id` transcript so assistant content renders before the live status pill, keeping streamed text visually anchored at the bottom of the message body instead of starting above the indicator.
- Replaced the single pulsing streaming dot with a sequential three-dot bouncing loader using Tailwind utility classes and staggered animation delays.
- Tightened the `.ChatMessages` sticky-scroll hook so a real upward user scroll disables autoscroll until the viewport returns near the bottom or the jump-to-bottom button is used.
- Stopped delegated placeholder rows from showing a streaming indicator before they emit thinking, content, or tool activity, while preserving the existing placeholder row itself.
- Added LiveView coverage proving a delegated placeholder renders without the streaming badge at creation time and gains it once stream chunks arrive.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- `mix precommit`

By: gpt-5.4 on Codex

## Follow-up adjustments

- Reworked the chat scroll hook to treat autoscroll as an explicit paused/resumed state rather than only a bottom-distance heuristic.
- Pauses now trigger immediately on upward wheel/touch interaction and stay paused while the user is away from the latest message, resuming only when they scroll back to bottom or use the jump-to-bottom action.
- Removed the streaming pill chrome and label text so the assistant live state is rendered as dots only.
- Moved the dot animation into `assets/css/app.css` with dedicated keyframes and staggered delays so the three-dot sequence animates reliably in the LiveView template.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- `mix precommit`

By: gpt-5.4 on Codex
