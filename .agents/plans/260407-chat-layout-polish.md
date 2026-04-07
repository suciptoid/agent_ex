## Problem

The `/chat/:id` follow-up polish request covers four UI adjustments:

1. Center the chat history column and cap it to the same `max-w-4xl` width as the composer.
2. Cap the composer textarea to half the viewport height for large inputs.
3. Remove the sidebar user-menu trigger border and make long user identity text truncate cleanly.
4. Fix the reasoning dropdown/composer overlap shown in the screenshot so the textarea content starts normally and the controls sit in a reserved bottom control row.

## Proposed approach

- Narrow the scroll container itself to a centered `max-w-4xl` shell so the history and composer line up visually.
- Rework the composer padding so the textarea keeps normal horizontal text padding, reserves bottom space for the floating controls, and auto-resizes up to `50vh`.
- Update the sidebar user trigger styling and text stack in `Layouts.dashboard/1` to avoid overflow with long emails.
- Re-run targeted chat/layout validation and the project precommit alias, documenting any unrelated baseline failures that remain.

## Todos

- `chat-history-width`: center the chat history column and align it with the composer width.
- `chat-input-sizing`: cap the textarea height and repair the reasoning dropdown/composer layout.
- `sidebar-user-trigger`: remove the trigger border and harden truncation for long user text.
- `chat-polish-validation`: run targeted validation and record any unrelated baseline failures.

## Notes

- The attached screenshot shows the composer text being pushed sideways because the dropdown reservation currently uses left padding instead of a reserved bottom control row.
- Existing unrelated `mix precommit` failures are still expected in:
  - `AppWeb.UserAuthTest`
  - `AppWeb.UserLive.LoginTest`
  - `App.UsersTest`
