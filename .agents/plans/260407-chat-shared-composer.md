## Problem

The `/chat` and `/chat/:id` pages render different message composer UIs. The new-chat screen still uses the older inline textarea, while the room screen has the newer floating composer shell and autosizing behavior.

## Proposed approach

- Extract the shared message form into `AppWeb.ChatComponents` so both pages render the same shell, textarea, submit button, and keyboard behavior from one component.
- Keep the room-only reasoning menu as an optional slot so `/chat/:id` can preserve its extra controls without forking the composer markup.
- Move the `ChatInput` colocated hook into the shared component and make the scroll-offset sync configurable so the room view keeps its floating overlay behavior while `/chat` can reuse the same input box without extra layout wiring.
- Update chat LiveView tests to assert the shared composer structure on both routes, then rerun targeted chat coverage and the repo precommit alias.

## Todos

- `chat-composer-plan`: capture the shared-composer approach and baseline validation context.
- `chat-composer-implement`: extract the composer component and render it from both chat pages.
- `chat-composer-tests`: align LiveView coverage with the shared DOM and rerun validation.

## Notes

- `mix precommit` currently has unrelated baseline failures in `AppWeb.UserAuthTest`, `AppWeb.UserLive.LoginTest`, and `App.UsersTest`.
- No router changes are needed; both chat routes already live in the existing authenticated `live_session :require_authenticated_user` scope behind the `[:browser, :require_authenticated_user]` pipeline.

## Follow-up

- Preserve the exact pre-extraction `/chat/:id` shell styling when sharing the composer. The extracted component should not introduce new rounding, borders, or shadows unless explicitly requested.
