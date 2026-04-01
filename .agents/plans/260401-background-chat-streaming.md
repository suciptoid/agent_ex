Problem: chat streaming is currently owned by the chat LiveView via Task.async and callbacks to the LiveView PID. Navigating away tears down the LiveView and stops the in-flight LLM run, which also risks interrupting delegated tool/agent work before the final assistant message is persisted.

Approach:
- Move primary chat streaming ownership into an app-supervised background process that is not linked to the LiveView.
- Persist the placeholder assistant message up front, stream updates from the worker, and publish UI updates over PubSub.
- Make the LiveView subscribe to room events and derive active streaming state from persisted messages so navigation does not cancel work.
- Keep cancel support by routing cancellation to the background worker instead of shutting down a LiveView-owned Task.
- Update tests to verify background completion survives leaving the chat room.

Todos:
- baseline-checks
- background-stream-worker
- liveview-pubsub-integration
- chat-tests-update
- final-validation

Notes:
- Chat route lives inside the existing authenticated browser scope and `live_session :require_authenticated_user` in `lib/app_web/router.ex`, which is correct because chat requires login and needs `@current_scope` assigned by the auth on_mount.
- Prefer Phoenix.PubSub plus a DynamicSupervisor/Registry-backed worker over a LiveView-owned Task.
- Preserve existing delegated-agent behavior, but make sure it now runs under the background worker lifecycle instead of the LiveView lifecycle.
