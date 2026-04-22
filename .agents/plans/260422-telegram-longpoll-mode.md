# 260422 — Telegram Longpoll Mode

## Problem
Telegram gateways currently assume webhook delivery only. We need to support a selectable update mode so organizations can run Telegram via either webhook or long polling, while preserving the in-progress channel approval work.

## Scope
1. Fix the pending-channel approval path so approval requires a mapped user.
2. Add gateway config for Telegram update mode with `webhook` default and `longpoll` option.
3. Add supervised Telegram long-poll runtime using `getUpdates` for active long-poll gateways.
4. Sync Telegram transport mode on create, edit, enable, disable, and app boot.
5. Add regression coverage for gateway form behavior, transport sync, and long-poll processing.

## Notes
- No router changes are needed for long polling because updates are pulled by a background worker instead of delivered to a new HTTP endpoint.
- Existing webhook route remains under the existing `:api` pipeline for webhook mode.
