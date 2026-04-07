## Chat floating composer pass

- Restored the sidebar user menu to the stock `menu_button` implementation and removed the custom popover wrapper from `Layouts.dashboard/1`.
- Rebuilt the `/chat/:id` composer as a single rounded glass card so the textarea, reasoning control, and send/cancel button all live inside the same bordered shell.
- Moved the composer into a floating bottom overlay and introduced a dynamic `--chat-composer-offset` spacer so the message list can scroll behind the composer without hiding the latest content.
- Updated the chat input resizing hook to keep the scroll offset in sync with the composer shell height.

## Validation

- `mix test test/app_web/live/chat_live_test.exs`
- Browser check on `/chat/:id` confirmed:
  - stock sidebar user menu wrapper restored (`w-fit`)
  - translucent composer shell with backdrop blur
  - send button inside the same bordered composer box
  - chat history scrolling underneath the floating composer
- `mix precommit` still fails only on the unchanged baseline tests:
  - `AppWeb.UserAuthTest`
  - `AppWeb.UserLive.LoginTest`
  - `App.UsersTest`
