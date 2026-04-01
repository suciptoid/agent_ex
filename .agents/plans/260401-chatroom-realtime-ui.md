Problem: chat room tool responses still use a custom collapsible control that exposes tool arguments in the message header, and cross-tab chat updates only become visible after the assistant stream advances or completes.

Approach:
- Switch tool response rendering in the chat room to `PUI.Accordion` so the UI uses the shared component library instead of the custom collapsible control.
- Remove tool argument previews from tool response labels while keeping tool names, status styling, and content intact.
- Broadcast newly created user messages over the existing chat room PubSub topic so other open tabs receive them immediately.
- Extend LiveView regression coverage for the accordion markup, hidden tool arguments, and cross-tab user message updates before assistant completion.

Todos:
- refactor-tool-accordion
- hide-tool-args
- broadcast-user-messages
- update-chat-tests

Notes:
- The chat route remains inside the existing authenticated browser scope and `live_session :require_authenticated_user` in `lib/app_web/router.ex`, which is correct because chat requires login and depends on `@current_scope` from the auth on_mount.
- Reuse the existing room-level PubSub topic in `App.Chat`; no new channel or transport layer is needed.
- Primary assistant streaming also needs PubSub fan-out during placeholder creation and incremental stream/tool events so secondary tabs stay live before completion.
- Client-side UI state also needs protection across LiveView patches: the chat form must explicitly leave loading mode when terminal stream updates arrive, and the mobile sidebar hook must restore its own client state instead of trusting patched DOM defaults.
