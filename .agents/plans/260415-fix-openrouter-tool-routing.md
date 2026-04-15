# Fix OpenRouter tool-routing failures

## Goal

Prevent chat runs from failing on OpenRouter models/providers that do not support tool use.

## Steps

1. Inspect runner and capability path for how tools are attached to LLM calls.
2. Add capability-based tool gating using provider model metadata (`supported_parameters`).
3. Add runtime fallback: on provider error `No endpoints found that support tool use`, retry once without tools.
4. Add focused tests and run precommit.

## Success criteria

- OpenRouter requests that fail solely due to unsupported tool use continue as normal chat responses (without tools).
- Models that advertise no tool support do not send tools.
- Existing tests stay green.
