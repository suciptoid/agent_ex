# Fix provider model refresh datetime precision

## Goal

Fix crash during provider model refresh caused by writing second-precision datetimes into `:utc_datetime_usec` fields.

## Steps

1. Locate refresh persistence code path and confirm second precision source.
2. Update persistence timestamps to microsecond precision for `provider_models` upsert/update and provider refresh marker fields.
3. Run focused validation and capture changelog entry.

## Success criteria

- Clicking **Refresh Models** no longer crashes LiveView.
- Provider model upserts complete successfully.
- No regressions in tests/lint for touched code.
