# 260422 — Org Settings Members And Chat Ribbon

## Scope
1. Rework the pending-channel approval UI so it floats as a ribbon over the chat room instead of occupying the main layout flow.
2. Add organization member management to `/organizations/settings` for existing users, including role selection.
3. Render gateway channel mappings using organization member identity labels (`name (email)` / email) instead of raw user IDs.

## Notes
- No router changes are needed for this pass.
- Member management is limited to adding existing registered users to the current organization.
