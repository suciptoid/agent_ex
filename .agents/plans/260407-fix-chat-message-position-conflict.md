# Fix chat message position conflict

## Problem

`Chat.create_message/2` allocated positions with `max(position) + 1` and trusted explicit positions blindly. During `ask_agent`, a delegated placeholder could grab the next slot before tool-result inserts, causing the tool message insert to hit the unique `(chat_room_id, position)` index.

## Approach

1. Make message insertion allocate positions inside a room lock.
2. If a requested explicit position is already taken, move the new message to the next available slot at or after that position.
3. Add regression coverage for the delegated placeholder/tool-message collision.

## Notes

- Keep the fix in the chat context so every caller benefits.
- Surface unique index violations as changeset errors instead of exceptions when a collision still slips through.
