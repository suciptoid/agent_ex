# 260409 — Telegram Group Message Troubleshooting

## Goal

- Verify why Telegram group messages are not reaching the gateway after `/start` succeeds.
- Add a product-side hint if the issue is caused by Telegram delivery rules rather than app logic.

## Plan

1. Re-read the webhook and Telegram handler flow to confirm the app accepts and processes group `message` updates.
2. Compare the observed behavior with Telegram bot delivery rules for groups.
3. Add a concise gateway-form note explaining the Telegram group requirement so the setup is self-serve.
4. Trace the webhook-to-chat UI path for external gateway messages and fix any missing LiveView broadcasts.
5. Re-run focused tests and `mix precommit`.
