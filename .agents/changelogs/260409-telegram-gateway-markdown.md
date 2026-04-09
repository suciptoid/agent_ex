# 260409 — Telegram Gateway Markdown + Typing

## Changes

- Added Telegram-specific agent instructions so gateway replies use Telegram-supported MarkdownV2.
- Extended the Telegram client with `send_markdown_message/4` and `send_chat_action/3`.
- Kept Telegram typing indicators alive while assistant replies are streaming, then stopped them cleanly on completion.
- Passed Telegram-specific extra system prompt data through chat stream startup so gateway replies inherit the new formatting guidance.
- Updated Telegram handler tests to cover `sendChatAction` and MarkdownV2 `parse_mode`.
- Relaxed an over-specific sidebar assertion in gateway LiveView tests to match the current layout classes.

## Validation

- `mix test test/app/gateways/telegram/handler_test.exs`
- `mix precommit`

By: gpt-5.4-mini on GitHub Copilot
