# 260422 — Org Settings Members And Chat Ribbon

- Updated the pending-approval chat UI in `lib/app_web/live/chat_live/show.html.heex` to render as a floating ribbon overlay pinned near the top of the chat room, with matching top padding so messages are not obscured.
- Added `App.Organizations.MemberForm` plus `Organizations.change_member_form/1`, `list_organization_members/1`, and `add_member_by_email/3` so organization settings can validate and add existing registered users with an explicit role.
- Extended `lib/app_web/live/organization_live/settings.ex` with a members section, an add-member modal, role options, and enriched mapping rendering so mapped users show member identity labels rather than raw UUIDs.
- Added and updated coverage in `test/app_web/live/organization_live/settings_test.exs` for member addition and mapped-user label rendering.
- Verification:
  - `mix test test/app_web/live/organization_live/settings_test.exs test/app_web/live/chat_live_test.exs`
  - `mix precommit`

By: gpt-5.4 on OpenCode
