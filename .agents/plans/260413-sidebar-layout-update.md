# Sidebar layout update

## Goal
- Restyle the dashboard sidebar surface to use `bg-secondary`.
- Increase vertical padding on chat history rows so entries are easier to click.
- Reorder the sidebar so the organization selector sits between the Dashboard item and the burger/menu area.
- Replace the empty space after the burger button with the `AgentEx` app name.

## Plan
1. Inspect the shared dashboard layout and confirm the current sidebar structure.
2. Patch the sidebar markup in `lib/app_web/components/layouts.ex` to reorder the top block and update spacing/classes.
3. Verify the updated layout with formatting and project checks.

