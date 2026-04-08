# Tools UI refactor

## Goal
- Simplify the tools list to a compact single-column layout with edit/delete actions.
- Simplify the shared tool create/edit form and infer runtime-vs-default parameter behavior from the default value field.

## Scope
- `lib/app_web/live/tool_live/index.ex`
- `lib/app_web/live/tool_live/create.ex`
- `lib/app/tools.ex`
- `test/app_web/live/tool_live/create_test.exs`

## Notes
- Keep `/tools/list`, `/tools/create`, and `/tools/:id/edit` in the existing authenticated LiveView scope because tools are user-owned records.
- Preserve the existing shared create/edit LiveView and simplify its UI instead of splitting create and edit into separate modules.
- Infer `source` from the default value during LiveView param normalization so the underlying schema and runtime behavior stay compatible.
