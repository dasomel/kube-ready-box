# Release evidence

Each immutable release is stored under `release-evidence/<version>/`.

## Stage machine

`tools/release-promote.sh promote` advances a release through three stages, one step per
invocation, tracked in `release-state.env` (`stage=...`):

```
candidate --promote--> staging --promote--> production
```

`production` and `rolled_back` (see Rollback below) are terminal: `promote` refuses to advance
from either, and refuses on any unrecognized stage. Every transition appends one line to
`release-evidence/<version>/promotion-log.tsv` (tab-separated: UTC timestamp, from_stage,
to_stage).

Gate per transition:

- **candidate → staging**: all 5 evidence files below must be present, non-empty, and
  structurally valid.
- **staging → production**: the same evidence check, PLUS full matrix coverage — every target
  in `required-matrix.txt` must appear in `verification.json` with status `PASS`
  (case-insensitive). Any missing or non-PASS target blocks promotion and is listed by name.

## Required evidence (candidate → staging gate)

- `verification.json` — provider/architecture/filesystem smoke-test matrix (must parse as JSON)
- `SHA256SUMS` — artifact integrity (checksum manifest, see format below — not JSON)
- `sbom.json` — SBOM (must parse as JSON)
- `security-report.json` — security scan (must parse as JSON)
- `license-report.json` — license evidence (must parse as JSON)
- `release-state.env` — candidate/staging/production/rolled_back state

## `verification.json` contract

Two shapes are accepted, so existing tooling (`test-vm/matrix.sh`) works without translation:

```json
{"results": [{"target": "vmware-arm64-ext4", "status": "PASS"}, ...]}
```

```json
{"cases": [{"target": "vmware-arm64-ext4", "status": "PASS"}, ...]}
```

Each item is matched against a line in `required-matrix.txt` by its `target` field. An item with
no `target` field satisfies nothing — it never counts toward matrix coverage. Status matching for
`PASS` is case-insensitive.

## `SHA256SUMS` format

Not JSON — a checksum manifest. Every non-blank line must match:

```
^[0-9a-f]{64}[ *][ ]?\S
```

i.e. a 64-character lowercase hex digest, then a space or `*` (binary/text mode marker), then an
optional space, then the filename. Example:

```
9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08  kube-ready-vmware-arm64.box
```

## Verification (`verify`)

```bash
VERSION=vX.Y.Z ./tools/release-promote.sh verify
```

Always checks: state file well-formed (`schema_version`, `version` matching `VERSION`, known
`stage`), and that `required-matrix.txt` is present.

- `stage=candidate`: evidence is not yet required. Reports readiness (e.g. `evidence: 3/5`,
  `matrix: 2/8 PASS`) and exits 0 if metadata is sound — the report always names how much
  evidence is actually present so it is never mistaken for an unqualified pass.
- `stage=staging` or `production`: all evidence must be present and valid, and (for `production`)
  the matrix must be fully covered. Any failure exits non-zero — reaching these stages without
  valid evidence means the gate was bypassed.
- `stage=rolled_back`: terminal; reported as informational, evidence is not re-checked.

## Rollback

Rollback means pinning a previously verified version. Published artifacts and Git tags are
retained; they are never deleted as part of rollback.

`PREVIOUS_VERSION` must be a genuine known-good — its `release-state.env` must show
`stage=staging` or `stage=production`. Rolling back to a `candidate` is refused.

```bash
VERSION=vX.Y.Z PREVIOUS_VERSION=vX.Y.Z-previous ./tools/release-promote.sh rollback
```

Effects:

- `release-evidence/rollback/rollback-pin.env` — the *current* pin (overwritten each rollback).
- `release-evidence/rollback/history.tsv` — immutable history, one line appended per rollback
  (UTC timestamp, from_version, to_version, reason).
- The rolled-back version's own `release-evidence/<VERSION>/release-state.env` is set to
  `stage=rolled_back`, and its `promotion-log.tsv` gets an entry recording the transition — so
  nothing about that version's history is silently lost.
