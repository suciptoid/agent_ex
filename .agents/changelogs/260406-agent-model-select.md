# Agent Model Select Dropdown

## Changes

- **`lib/app_web/live/agent_live/form_component.ex`**:
  - Replaced the plain text input for the "Model" field with a searchable `PUI.Select` dropdown
  - Added `model_options_for_provider/2` helper that calls `ReqLLM.available_models/1` scoped to the selected provider, passing the provider's API key via top-level `api_key:` option
  - On `update/2`, computes initial model options from the agent's current `provider_id` (supports edit flow)
  - On `validate`, always recomputes model options from the changeset's `provider_id` so switching providers refreshes the list
  - Fix: `provider_options: [api_key: ...]` did not work for auth resolution; switched to top-level `api_key:` which `ReqLLM.Auth.resolve` picks up correctly
