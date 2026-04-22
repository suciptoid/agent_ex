# 260422 — Gateway Message User Mapping

## Scope
1. Ensure channel-originated user messages persist the mapped organization `user_id`.
2. Pass the mapped `user_id` into agent runner context so user-scoped memories stay isolated.
3. Backfill historical channel user messages when a pending channel is approved.
4. Add regression coverage for persisted `user_id`, runner context `user_id`, and approval backfill.
