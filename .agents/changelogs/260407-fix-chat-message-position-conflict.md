# Fix chat message position conflict

- Made `App.Chat.create_message/2` allocate message positions inside a room-scoped transaction and lock, so concurrent inserts no longer race on `chat_messages_chat_room_id_position_index`.
- When a caller requests an explicit `position` that is already occupied, the insert now moves to the next available slot at or after that position instead of raising.
- Registered the room/position and parent-tool-call unique indexes on `App.Chat.Message.changeset/2` so any unexpected collisions surface as normal changeset errors.
- Updated `App.Chat.StreamWorker` to advance tool positions from the actual persisted tool message slot, so follow-up assistant updates do not target a now-occupied position.
- Added regression coverage for both the direct delegated-placeholder/tool-message collision and the full streaming `ask_agent` ordering that previously raised during tool persistence.
- `mix test test/app/chat_test.exs` and `mix test test/app_web/live/chat_live_test.exs` passed; `mix precommit` still reports the pre-existing unrelated failures in `AppWeb.UserLive.LoginTest`, `AppWeb.UserAuthTest`, and `App.UsersTest`.
