# Auth Simple Clean Redesign Plan

1. Capture design context for impeccable skill in `.impeccable.md` based on confirmed audience and tone.
2. Redesign auth LiveViews (`login`, `registration`, `forgot_password`, `reset_password`) to a consistent calm/compact/simple visual system.
3. Keep implementation Tailwind utility-only in templates (no colocated CSS additions).
4. Preserve existing auth behavior and IDs/events used by tests and flows.
5. Run `mix precommit` and resolve any issues.
6. Write changelog entry under `.agents/changelogs/260413-auth-simple-clean-redesign.md`.
