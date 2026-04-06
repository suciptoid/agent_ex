# Chat agent dropdown styling changelog

## Summary
- Switched the add-agent control in `AppWeb.ChatComponents.chat_agent_selector/1` off the unstyled `PUI.Dropdown` path.
- Kept the existing dashed pill trigger UI by overriding the styled PUI button classes instead of rendering a raw button.

## Changes
- `lib/app_web/components/chat_components.ex`
  - changed the add-agent `<.menu_button>` from `variant="unstyled"` to `variant="outline"`
  - kept `content_class="w-56"` so the menu width stays the same
  - added class overrides (`h-auto`, `rounded-full`, `border-dashed`, `shadow-none`, custom hover colors) so the trigger still matches the previous UI

## Result
- PUI now handles the dropdown menu surface/background, animation, and hidden/visible behavior again.
- The trigger still looks like the previous custom add-agent pill.

## Validation
- `mix test test/app_web/live/chat_live_test.exs`
- `mix precommit` still reports the same unrelated baseline failures in auth/login tests
