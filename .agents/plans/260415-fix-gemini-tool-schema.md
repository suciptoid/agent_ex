# Fix Gemini tool schema compatibility

## Goal

Fix streaming failures on Gemini caused by unsupported JSON schema keywords in tool definitions.

## Steps

1. Inspect where tool schemas are built and sent to Alloy providers.
2. Add adapter-aware schema sanitization for Gemini/Google providers (strip unsupported keys like `additionalProperties`).
3. Validate with focused tests/checks and record changelog.

## Success criteria

- Gemini requests no longer fail with `Unknown name "additionalProperties"`.
- Existing non-Gemini tool workflows remain unchanged.
