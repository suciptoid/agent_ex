# Remove `provider_type`

- Remove `provider_type` from the provider schema, form, tests, and Alloy/backend type resolution.
- Keep `provider` as the single source of truth for provider classification.
- Update the existing migration file to stop adding/backfilling `provider_type`.
- Run the relevant test subset, then `mix precommit`.
