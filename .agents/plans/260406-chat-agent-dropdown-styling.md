# Chat agent dropdown styling plan

## Problem
- The add-agent control in `AppWeb.ChatComponents.chat_agent_selector/1` uses `PUI.Dropdown`, but it still passes `variant="unstyled"` to `<.menu_button>`.
- In unstyled mode, PUI skips the dropdown surface classes that handle hidden/visible state styling and the popover background, so the list appears wrong.

## Approach
1. Remove `variant="unstyled"` from the add-agent `<.menu_button>`.
2. Preserve the current dashed pill trigger UI with `class` overrides on the styled PUI button.
3. Keep the dropdown content on the default styled path so PUI handles background, border, animation, and visibility.
4. Validate with the chat-focused test file and compile/precommit context as needed.
