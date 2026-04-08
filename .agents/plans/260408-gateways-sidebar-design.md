# Gateways sidebar design

## Problem

The `Gateways` sidebar item under `Agents` is rendered with a smaller icon, tighter spacing, and muted text styles that make it look inconsistent with the rest of the navigation.

## Approach

1. Update the shared sidebar markup so the `Gateways` link uses the same nav sizing, spacing, and weight as the other sidebar items while staying visually nested under `Agents`.
2. Extend the existing LiveView regression test to assert the sidebar link keeps the expected navigation classes.
3. Re-run the relevant checks and compare `mix precommit` against the current baseline.

## Notes

- Keep the route placement unchanged; this is a sidebar presentation fix only.
- Preserve the existing collapsed-sidebar behavior and the `Agents` -> `Gateways` grouping.
