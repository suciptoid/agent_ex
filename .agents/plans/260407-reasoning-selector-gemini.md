Problem: Selecting reasoning in chat can fail in two ways: the default option forwards `nil` to ReqLLM for Gemini-compatible models, and the menu click payload uses a conflicting `"value"` key that trips the LiveView validation and flashes "Unsupported reasoning level".

Approach:
- Update the LiveView reasoning option mapping to treat the default selection as an explicit supported value and avoid leaking `nil`.
- Change the menu payload key to a dedicated parameter so browser clicks send the expected effort value.
- Extend LiveView coverage to exercise the real menu item click path and the default forwarding path.

Todos:
- fix-reasoning-flow
- add-reasoning-tests
- validate-reasoning-fix

Notes:
- The reasoning selector lives in the authenticated chat LiveView route already in the existing `live_session :require_authenticated_user` scope, so no router changes are needed.
