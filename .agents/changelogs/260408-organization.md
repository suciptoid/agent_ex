# 260408 organization

- Expanded `.agents/plans/260408-organization.md` into an execution plan covering data model, auth/session routing, org-scoped contexts, UI, and tests.
- Added organization foundations:
  - `organizations` and `organization_memberships` schemas/context
  - embedded organization settings with `default_agent_id`
  - migration to create org tables, backfill owner organizations, and move providers/tools/agents/chat rooms to `organization_id`
- Refactored runtime scoping:
  - `App.Users.Scope` now carries `organization` and `organization_role`
  - providers/tools/agents/chat contexts now scope by `organization_id`
  - agent runtime tool resolution now loads custom tools by organization instead of user
- Added authenticated organization flow:
  - active organization is resolved from session in `AppWeb.UserAuth`
  - org selection redirect and active-org enforcement plug
  - authenticated organization switch controller route
  - new `AppWeb.OrganizationLive.Select` page with create-organization modal
- Started UI migration:
  - dashboard layout now includes an organization switcher slot and all dashboard-style pages pass `@sidebar_organizations`
  - provider/tool/agent management pages started enforcing owner/admin-only controls and redirects
- Current checkpoint state:
  - `mix compile` passes
  - tests have not been updated yet
  - dashboard/chat auto-switch and remaining role-aware polish still need finishing

## Completion update

- Finished cross-org auto-switching in `AppWeb.ChatLive.Show`, so opening a chat from another accessible organization now updates the active org session and lands on the requested room.
- Made `DashboardLive` organization-aware with workspace/role badges and member-safe primary actions and messaging.
- Fixed the organization migration for clean test-database bootstraps by backfilling binary UUID ids correctly and avoiding duplicate foreign-key creation on later `modify` calls.
- Added organization-aware test fixtures and active-organization session helpers, then updated context, auth, controller, LiveView, and runtime tool tests to the new org-scoped behavior.
- Updated stale auth/login expectations to the org-selection flow and narrowed the existing magic-link password test to the intended user row.
- Final validation completed with `mix precommit`.

## Post-validation bug fix

- Fixed the active-organization restore path in `AppWeb.UserAuth`: authenticated requests now always honor the session's `active_organization_id`, instead of only doing so when `current_scope` was already assigned earlier in the same request.
- Added end-to-end coverage for creating a new organization from the selector and immediately entering the workspace, plus a direct auth regression test for multi-org session restoration.
- Re-ran `mix precommit` after the fix.
