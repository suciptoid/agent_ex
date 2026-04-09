# 260409 — Telegram Group Gateway + Gateway Pages

## Goal

- Make Telegram gateways work for group chats in addition to private chats.
- Change `/gateways/new` and `/gateways/:id/edit` from modal-driven flows into dedicated pages.

## Constraints

- Keep gateway management routes inside the existing authenticated active-organization router scope:
  - `scope "/", AppWeb`
  - `pipe_through [:browser, :require_authenticated_user, :active_organization_required]`
  - `live_session :require_active_organization`
- Reuse the existing gateway form logic where possible.
- Preserve Telegram webhook sync behavior on create, edit, and enable.

## Plan

1. Replace gateway modal navigation with dedicated LiveViews for new/edit while keeping the same authenticated router session and organization context.
2. Refactor the gateway form component so it can render as a full page card and navigate back to `/gateways` after save.
3. Update Telegram message handling so group chats use a stable channel/chat label and per-message sender names instead of private-chat assumptions.
4. Add regression coverage for dedicated gateway pages and Telegram group chat handling.
5. Run targeted tests and `mix precommit`, then record the final changelog.
