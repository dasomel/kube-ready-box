# OpenForge status schema source

`openforge-status.schema.json` is a byte-for-byte copy of
`portfolio/status.schema.json` in `dasomel/openforge`
(fetched 2026-09-07 via `gh api repos/dasomel/openforge/contents/portfolio/status.schema.json`,
upstream `main` at d702363e24bbb56d5e28aec9e7fb20a56c1ea519).

Refresh it the same way before changing `tools/openforge-project-status.sh`;
the script validates its payload against this copy, so a stale copy means a
payload that upstream CI may reject.
