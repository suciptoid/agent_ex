# Changelog 2026-04-01

## Dashboard padding & chat layout
- Moved inner padding out of `Layouts.dashboard/1` and into each dashboard-backed page so individual views now own their spacing.
- Updated the chat room screen so the header border spans the full width, the chat container stays borderless/square, and the message input is no longer wrapped in a card-style container.
- Verified the app compiles after the layout changes.
