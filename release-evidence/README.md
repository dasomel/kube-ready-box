# Release evidence

Each immutable release is stored under `release-evidence/<version>/`.

Required evidence before staging promotion:

- `verification.json` — provider/architecture/filesystem smoke-test matrix
- `SHA256SUMS` — artifact integrity
- `sbom.json` — SBOM
- `security-report.json` — security scan
- `license-report.json` — license evidence
- `release-state.env` — candidate/staging/production state

Rollback means pinning a previously verified version. Published artifacts and Git tags are retained; they are never deleted as part of rollback.
