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
  structurally valid, and the content gates below must hold.
- **staging → production**: the same evidence check, PLUS full matrix coverage — every target
  in `required-matrix.txt` must appear in `verification.json` with status `PASS`
  (case-insensitive). Any missing or non-PASS target blocks promotion and is listed by name.

Content gates (both transitions, bash `release-promote.sh` and the Rust `verify-evidence`
cross-check apply identical rules):

- `security-report.json` and `license-report.json` must have `status` exactly `PASS` (no
  trimming). `FAIL`, any other value, or a missing `status` blocks. `UNKNOWN` blocks unless
  `ALLOW_UNKNOWN_EVIDENCE=1` is set (prints a warning); the opt-in applies to BOTH
  transitions (candidate → staging and staging → production).
- `SHA256SUMS` must list at least one entry, use LF line endings (CR is rejected), and every
  listed file must exist and match its hash. Entries are resolved under `ARTIFACT_DIR`
  (default: this release directory); real releases list the `.box` digests that live in
  `packer/dist`, so run with `ARTIFACT_DIR=packer/dist`. A missing listed file blocks; there
  is no option to skip hashing. Entries with `..`, absolute paths, or symlinks resolving
  outside `ARTIFACT_DIR` are rejected. The `*` binary marker (`sha256sum -b`) is accepted.

## Required evidence (candidate → staging gate)

- `verification.json` — provider/architecture/filesystem smoke-test matrix (must parse as JSON)
- `SHA256SUMS` — artifact integrity (checksum manifest, see format below — not JSON; listed files must exist under `ARTIFACT_DIR` and hash correctly)
- `sbom.json` — SBOM (must parse as JSON)
- `security-report.json` — security scan (must parse as JSON, `status` must be `PASS`)
- `license-report.json` — license evidence (must parse as JSON, `status` must be `PASS`)
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
optional space, then the filename. The file must contain at least one entry, and CRLF line
endings are rejected. Example:

```
9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08  kube-ready-vmware-arm64.box
```

## Verification (`verify`)

```bash
# SHA256SUMS lists the .box digests; point ARTIFACT_DIR at the directory holding them.
ARTIFACT_DIR=packer/dist VERSION=vX.Y.Z ./tools/release-promote.sh verify
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
