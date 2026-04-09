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

## Follow-up Fix

- Fixed Telegram delivery for normal assistant text under `MarkdownV2`: the client now retries `sendMessage` with an escaped MarkdownV2 payload when Telegram returns a `can't parse entities` error.
- Added a regression test that simulates Telegram rejecting the first raw MarkdownV2 attempt and verifies the escaped retry is sent successfully.
- Added explicit logging for failed Telegram assistant reply delivery after retries.

By: gpt-5.4 on GitHub Copilot

## Formatting Guardrails

- Strengthened the Telegram gateway prompt so agents explicitly avoid tables, GitHub/CommonMark formatting, and `**bold**`, and prefer bullet lists or `Label: value` lines.
- Added Telegram client normalization for common non-Telegram markdown, including converting `**bold**` to Telegram-style bold.
- Added a table-specific safeguard that rewrites markdown tables into readable plain text before sending, so Telegram users never see raw pipe tables.
- Added `test/app/gateways/telegram/client_test.exs` to cover both the table rewrite path and double-asterisk bold normalization.

By: gpt-5.4 on GitHub Copilot

## MarkdownV2 Sanitizing

- Read Telegram's `formatting-options` and `MarkdownV2 style` docs to align the gateway with supported entities and escaping rules.
- Changed the Telegram client to sanitize MarkdownV2 before the first send, preserving supported markers like `*bold*`, `_italic_`, `__underline__`, `~strikethrough~`, `||spoiler||`, inline code, fenced code blocks, and blockquotes while escaping surrounding reserved characters.
- Added `Logger.warning/1` when Telegram rejects a MarkdownV2 payload and the client falls back to plain text.
- Expanded Telegram client coverage with a screenshot-shaped regression test proving bold survives while punctuation is escaped, plus a warning/fallback test for markdown rejection.

By: gpt-5.4 on GitHub Copilot
