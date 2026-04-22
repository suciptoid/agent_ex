## 260422 - Channel User Mapping & Approval Flow

**Summary**: Implemented user mapping for gateway channels (starting with Telegram) so external users can be mapped to app users. Unmapped users create channels in a pending-approval state, preventing agent responses until an admin approves and maps them.

### Changes Made

1. **Migration** (`priv/repo/migrations/20260422081834_add_approval_status_to_gateway_channels.exs`)
   - Added `approval_status` column (string, default: "approved", not null) to `gateway_channels`
   - Added index on `approval_status`

2. **Channel Schema** (`lib/app/gateways/channel.ex`)
   - Added `@approval_statuses [:approved, :pending_approval, :rejected]`
   - Added `approval_status` field with Ecto.Enum, default `:approved`
   - Updated changeset to cast and validate `approval_status`

3. **Gateways Context** (`lib/app/gateways.ex`)
   - `find_or_create_channel/2` now checks if the external user is mapped to an app user via org secrets
   - If unmapped, new channels get `approval_status: :pending_approval`
   - If mapped, channels get `approval_status: :approved` (existing behavior)
   - Added `channel_pending_approval?/1` helper
   - Added `approve_channel/3` — approves a pending channel and stores the user mapping
   - Added `reject_channel/1` — rejects a pending channel (blocks it)
   - Added `get_mapped_user_id/3` — looks up mapping via org secret
   - Added `put_channel_user_mapping/3` — stores mapping as org secret
   - Added `list_channel_user_mappings/1` — lists all mappings for an org
   - Added `delete_channel_user_mapping/2` — removes a mapping
   - Added `get_channel_by_chat_room_id/1` — fetches channel by chat room

4. **Organizations Context** (`lib/app/organizations.ex`)
   - Made `put_secret_value/3` public (was private `put_secret`) so Gateways context can store mappings

5. **Telegram Handler** (`lib/app/gateways/telegram/handler.ex`)
   - `send_to_chat_room/4` now checks if channel is pending approval
   - If pending: broadcasts the user message but skips agent stream start
   - Sends a Telegram message: "Your message has been received and is pending approval..."
   - Added `relay_pending_approval_message/2`

6. **Chat Context** (`lib/app/chat.ex`)
   - `list_chat_rooms_for_sidebar/1` now includes `approval_needed` flag
   - Added `sidebar_pending_approval_chat_room_ids/1` helper

7. **Sidebar Layout** (`lib/app_web/components/layouts.ex`)
   - Shows `hero-exclamation-triangle` warning icon (amber) for rooms with `approval_needed: true`
   - Gateway icon is hidden when approval is needed

8. **ChatLive.Show** (`lib/app_web/live/chat_live/show.ex` + `.html.heex`)
   - Loads `pending_channel` and `organization_users` when viewing a pending room
   - Shows an amber approval banner at the top with:
     - External user info
     - Dropdown to select an organization user to map to
     - Reject button
   - Added `handle_event("approve-channel", ...)` — maps user + approves channel
   - Added `handle_event("reject-channel", ...)` — rejects the channel

9. **Organization Settings** (`lib/app_web/live/organization_live/settings.ex`)
   - Added "Channel User Mappings" section
   - Lists all existing mappings in a table (gateway type, external user ID, mapped user ID)
   - Allows deleting mappings
   - Informative empty state explaining mappings are auto-created on approval

10. **Tests**
    - Updated Telegram handler test setup to pre-seed user mapping so channels are auto-approved
    - Updated chat live test to pre-seed mapping for gateway-linked room test
    - All 227 tests pass

By: openrouter/moonshotai/kimi-k2.6 on OpenCode
