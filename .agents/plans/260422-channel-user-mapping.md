# Channel User Mapping & Approval Flow

## Problem
When Telegram users start a conversation via a gateway channel, they are not mapped to any app user. There's no way to control which Telegram user corresponds to which app user.

## Solution

### 1. Database: Add `approval_status` to `gateway_channels`
- New enum field: `pending_approval`, `approved`, `rejected`
- Default: `approved` (existing channels work as before)

### 2. User Mapping via Organization Secrets
- Store mappings as org secrets with key pattern: `channel_user_map:{gateway_type}:{external_user_id}` → `app_user_id`
- Add helper functions in `App.Gateways` context

### 3. Channel Creation Flow
- When a new channel is created and the external user is NOT mapped → set `approval_status: :pending_approval`
- When user IS mapped → `approval_status: :approved` (current behavior)

### 4. Telegram Handler Changes
- When channel has `pending_approval` status: create the user message, store it, but DON'T start agent stream
- Send a brief message to the Telegram user: "Your message is pending approval"

### 5. Sidebar UI
- Show warning icon (hero-exclamation-triangle) for rooms with pending channels

### 6. Chat Room UI (Show)
- When opening a pending room: show approve/reject banner
- On approve: show user mapping dropdown to select an app user
- On reject: close/block the channel

### 7. Org Settings
- Add "Channel User Mappings" section to manage existing mappings
- Show mapped external users → app users
- Allow adding/removing mappings
