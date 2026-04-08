# Organization workspace migration

## Goal
- Introduce organizations as the workspace boundary for providers, user-defined tools, user-defined agents, and chat rooms.
- Replace direct `user_id` scoping on workspace assets with organization scoping.
- Keep authentication user-based, but persist the active organization in the user session.

## Product rules
### Workspace ownership
- An organization owns:
  - providers
  - user-defined tools
  - user-defined agents
  - chat rooms
- Organization settings live on the organization schema as an embedded settings struct so we can add defaults over time. For now it stores `default_agent_id` and defaults to `nil`.

### Membership model
- Users can belong to many organizations.
- Organizations can have many users through memberships.
- Membership roles:
  - `owner`: full access, exactly one per organization
  - `admin`: same operational rights as owner
  - `member`: can use the workspace and create chat rooms, but cannot manage providers, tools, or agents

### Session and navigation
- The active organization id is stored in the user session.
- If the user has no organizations after authentication, route them to organization selection and prompt them to create one.
- If the user has exactly one organization, auto-activate it.
- If the user has multiple organizations and no valid active organization in session, route them to organization selection.
- If the user opens an org-owned asset from another organization they can access, switch the active organization and continue on that asset.

## Router plan
- Keep account-only routes under `scope "/", AppWeb` with `pipe_through [:browser, :require_authenticated_user]` and the authenticated live session so settings and organization selection still work before an active org exists.
- Add a second authenticated scope with `pipe_through [:browser, :require_authenticated_user, :require_active_organization]` for `/dashboard`, `/providers`, `/tools`, `/agents`, and `/chat` because those screens are workspace-bound and should never boot without a selected organization.
- Add an authenticated controller route for switching the active organization in session so the sidebar switcher works from any page.

## Execution plan
### 1. Data model and migration
- Create `organizations` and `organization_memberships`.
- Backfill one owner organization per existing user.
- Add `organization_id` to providers, tools, agents, and chat rooms, backfill from the generated owner organization, then remove user-only scoping.
- Update indexes and uniqueness constraints to be organization-based.

### 2. Organization context and scope
- Add organization schemas, settings embed, membership helpers, and permission helpers.
- Extend `App.Users.Scope` with `organization` and `organization_role`.
- Load the active organization during request/session auth and expose accessible orgs for the sidebar switcher.

### 3. Auth, redirects, and session switching
- Update login and authenticated routing so post-login lands on org selection or the active workspace as needed.
- Add active-org enforcement plug for workspace routes.
- Add organization switching endpoint that updates session and redirects back safely.

### 4. Org-scoped contexts
- Refactor providers, tools, agents, and chat queries/mutations to scope by organization.
- Enforce manager permissions for providers/tools/agents.
- Keep chat room usage available to all members.
- Validate provider/agent/chat associations stay inside the active organization.

### 5. UI and UX
- Add organization selection page with create-organization modal and post-create activation.
- Replace the sidebar logo/title block with an organization switcher that includes a footer action for creating a new organization.
- Update dashboard copy and action visibility to reflect the active organization and membership role.

### 6. Tests
- Add organization fixtures and update authenticated helpers to support an active organization session.
- Update context, controller, and LiveView coverage for org selection, session activation, permissions, and org-scoped assets.

## Status
- Done: detailed implementation plan
- Done: organization data model, migrations, scope, and core context refactor
- Done: authenticated organization flow, sidebar switcher, org selection/create UX, and safe org switching
- Done: cross-org asset switching for workspace routes, including chat rooms
- Done: role-aware dashboard plus manager-only provider/tool/agent management surfaces
- Done: org-aware fixtures, auth/session helpers, context/live/controller test updates, and runtime tool resolution coverage
- Done: final validation with `mix precommit`

## Delivery notes
- Account settings, password update, and organization selection stay in the authenticated-but-org-optional scope so they can boot before an active workspace exists.
- Dashboard, providers, tools, agents, and chat stay in the authenticated-and-org-required scope because they all depend on `current_scope.organization`.
- Fresh database setup now works end to end: the org backfill migration uses binary UUID values correctly and keeps the original foreign-key constraints intact while tightening nullability.
- Active organization selection is now restored from the session on every authenticated request, which fixes the create-and-switch flow for users who belong to multiple organizations.
