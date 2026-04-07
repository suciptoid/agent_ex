Problem: The provider form still uses a hardcoded dropdown list, so it can drift from the provider metadata exposed by ReqLLM and LLMDB.

Approach: Centralize provider option generation in the providers context, build the list from the libraries' provider catalogs, and reuse that same source for validation and the LiveView form.

Todos:
- Inspect the current provider form and validation path.
- Add a library-backed provider options helper.
- Wire the LiveView form to the helper.
- Add coverage that the new provider page exposes library-backed options.

Notes:
- Keep the change scoped to provider selection; do not alter unrelated agent/tool flows.
