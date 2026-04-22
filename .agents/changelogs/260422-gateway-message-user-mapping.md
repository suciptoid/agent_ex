# 260422 — Gateway Message User Mapping

- Fixed gateway-originated Telegram user messages so they persist the mapped organization `user_id` instead of remaining anonymous when a channel has an approved member mapping.
- Updated `lib/app/gateways/telegram/handler.ex` to pass the mapped `user_id` into `Chat.start_stream/4`, which keeps memory middleware scoped to the correct organization member and prevents recall from another mapped user.
- Updated `lib/app/gateways.ex` with `mapped_user_id_for_channel/1` and approval-time backfill for existing channel user messages in the same chat room, so pending messages created before approval are reassigned once a member mapping is approved.
- Extended the preloaded runner stub and `test/app/gateways/telegram/handler_test.exs` to verify persisted `user_id`, runner `user_id` context, and approval backfill behavior.
- Verification:
  - `mix test test/app/gateways/telegram/handler_test.exs`
  - `mix precommit`

By: gpt-5.4 on OpenCode
