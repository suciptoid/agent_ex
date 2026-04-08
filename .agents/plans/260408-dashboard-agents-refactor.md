# Dashboard and agents refactor

## Problem
- `/dashboard` is effectively placeholder UI right now, so it is not useful once a user signs in.
- `/agents` needs a simpler, denser presentation that matches the information users actually need when scanning agents.
- `/agents/new` is currently implemented as a modal route state on the index page, but it should be a full page.

## Approach
1. Add lightweight, user-scoped dashboard queries for real counts and recent activity.
2. Replace the dashboard placeholder cards with actionable overview, recent conversations, and setup/next-step surfaces.
3. Redesign the agents index into a single-column card list that only shows name, provider, model name, tool count, and icon actions.
4. Route `/agents/new` to a dedicated authenticated LiveView page while keeping edit/delete behavior intact.
5. Update the LiveView tests around the dashboard and agent creation flow.

## Todos
- Refactor dashboard data and UI.
- Redesign the agents index.
- Move new-agent flow to a dedicated page.
- Refresh dashboard and agent LiveView tests.

## Notes
- Keep the route in the existing `scope "/", AppWeb` block with `pipe_through [:browser, :require_authenticated_user]` and the existing `live_session :require_authenticated_user` so `@current_scope` is assigned consistently.
- Prefer sharing the current form component logic instead of creating a second copy of the agent form.
