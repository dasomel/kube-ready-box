# Portfolio Engineering/Supply-Chain Contract (#28)

kube-ready-box's local instantiation of the Dasomel OSS Portfolio's common
build/CI/SBOM/license/provenance/release contract (Narwhal #161). Per that
contract's own stated principle, this repo stays fully standalone
buildable/releasable — the common vocabulary is adopted where it fits this
repo's actual Packer/Vagrant/multi-OS shape, not imposed where it wouldn't.

## Common Make targets

Narwhal #161's vocabulary: `help, fmt, lint, test, security, license, sbom,
build, package, e2e, clean, release`. All twelve exist in the root
`Makefile`, each a thin wrapper around an existing tool — see `make help`
for the exact command each one runs. None of them reimplement anything;
`make build` is `packer/build.sh`, `make release` is
`tools/release-promote.sh`, etc.

## Common CI stage vocabulary

Narwhal #161's vocabulary: `validate, test, security, license, sbom, build,
package, e2e, release, attest`. Mapped against what actually runs today,
honestly — not every stage is CI-automated:

| Stage | Where | Status |
|---|---|---|
| `validate` | `.github/workflows/validate.yml`: `packer` (packer validate x4 provider/arch x2 filesystem), `shellcheck` (shellcheck + actionlint) | automated, every PR |
| `test` | `validate.yml`: `rust` (cargo check/build/test), `contract-syntax` (JSON schema smoke + aggregator) | automated, every PR |
| `security` | `validate.yml`: `supply-chain-guard` (#30 unpinned-input static check), `supply-chain-negative-tests` (live egress-block + checksum-substitution tests) | automated, every PR |
| `license` | `validate.yml`: `license` job (`tools/sbom-license-gate.sh`) | automated, every PR (added this pass — the script was previously orphaned, wired to nothing) |
| `sbom` | `packer/scripts/generate-sbom.sh`, runs **inside the guest** during a real box build | NOT CI-automated — only exercised when an actual Packer build runs (`build-amd64.yml`/`build-arm64.yml`/`build-nixos.yml`), which validate.yml deliberately doesn't do (too slow/resource-heavy for a PR gate) |
| `build` / `package` | `.github/workflows/build-amd64.yml`, `build-arm64.yml`, `build-nixos.yml` | automated, but as separate on-demand/scheduled workflows, not part of the PR-gating `validate.yml` |
| `e2e` | `test-vm/matrix.sh` (boots built boxes and runs `verify_box.sh`) | **manual/local only** — needs a real hypervisor with the actual box files present, not wired into any GitHub Actions workflow |
| `release` | `tools/release-promote.sh` (candidate → staging → production, #8) | **manual/local only**, by design (a human decides when to promote) |
| `attest` | `tools/node-readiness-attest.sh`, wired into the aggregator as the `readiness` report | automated, every PR (as part of `contract-syntax`) |

## SBOM metadata

Narwhal #161's minimum field set: `artifact, digest, source, version,
license, supplier, build_id, commit_sha, workflow_run, platform/arch,
provenance, timestamp`. `packer/scripts/generate-sbom.sh`'s
`manifest.json` (schema_version 3, this pass) now carries all of these
except `digest` — see below for why that one's deliberately absent:

| Field | Source |
|---|---|
| `artifact`, `name` | `dasomel/ubuntu-${VERSION_ID}` |
| `source` | static: `https://github.com/dasomel/kube-ready-box` |
| `version` | `packer/build.sh` → `PKR_VAR_box_version` (`git describe --tags --always`) |
| `license` | static: `MIT` (this repo's `LICENSE`) |
| `supplier` | static: `dasomel` |
| `build_id` | `packer/build.sh` → `PKR_VAR_build_id` (`${GITHUB_RUN_ID:-local}-<timestamp>`) |
| `provenance.commit_sha` | `packer/build.sh` → `PKR_VAR_commit_sha` (`git rev-parse HEAD`) |
| `provenance.workflow_run` | `packer/build.sh` → `PKR_VAR_workflow_run` (GH Actions run URL, or `local`) |
| `architecture` | `dpkg --print-architecture` (in-guest, real) |
| `timestamp`, `build_date` | in-guest `date -u`, real build time |

`digest` (the box artifact's own checksum) isn't in `manifest.json` because
it can't be — `generate-sbom.sh` runs *inside the guest, before the box is
packaged*; the box doesn't have a digest yet at that point. The box's
digest lives in `release-evidence/`'s `SHA256SUMS` instead, computed after
packaging. Linking the two (which SBOM belongs to which box digest) needs
`build_id`, which both now carry — that's the join key, not a shared
`digest` field.

All four provenance vars are threaded from `packer/build.sh` through
Packer's `PKR_VAR_*` convention (picked up automatically, same idea as
Terraform's `TF_VAR_*`) into each `packer/*.pkr.hcl` template's
`environment_vars`, and from there into the guest as plain shell env vars.
A manual `packer build` invocation outside `build.sh` gets the pkr.hcl
variable defaults (`"unknown"`/`"local"`) instead of silently-absent
fields.

## License policy

Reconciled two previously-separate, both-orphaned tools into one, this
pass:

- `tools/license-gate.sh` and `etc/license-policy.txt` (a plain SPDX-ID
  denylist) — **removed**. It checked whether an SPDX identifier string
  literally appeared inside a dpkg package inventory line, which never
  happens (dpkg metadata doesn't carry normalized SPDX IDs) — it was
  non-functional as well as unwired.
- `tools/sbom-license-gate.sh` + `etc/license-policy.conf`
  (`DENY_LICENSES`/`DENY_PACKAGES`) — kept, as the one real license gate.
  It queries dpkg directly (respects `ROOT=` for a mounted image, fixed
  this session — see `docs/build-inputs.md`), embeds the full package
  list as evidence, and now emits single-line compact JSON (was
  pretty-printed, which silently broke `tools/kube-ready-contracts.sh`'s
  `tail -n 1` evidence parsing — another orphaned-script bug this
  consolidation surfaced). Wired into both the aggregator
  (`RUN_LICENSE_GATE=1`) and a dedicated `license` CI job, this pass.

**Fixed a real bug this pass**: `POLICY_FILE` defaulted to
`$ROOT/etc/vagrant-box/license-policy.conf` — a real in-guest path, but no
Packer provisioner has ever copied `etc/license-policy.conf` there, in
either CI (`ROOT=/`, the ephemeral runner) or a real box build. The
default silently fell back to a placeholder deny-list
(`GPL-3-only-AND-proprietary-placeholder`, matching no real SPDX ID) and
empty `DENY_PACKAGES` — the repo's committed policy had never actually
been enforced anywhere. Default is now resolved relative to the script's
own location (`etc/license-policy.conf`, next to `tools/`), independent of
`ROOT` (which stays purely about where the package *database* is read
from — real host, mounted image, or booted guest).

**License exception process** (Narwhal #161 asks for "repo별 예외를
명시적으로 승인"): `etc/license-exceptions.tsv`, a structured
package/reason/approved_by/approved_date record consumed by
`sbom-license-gate.sh`. A `DENY_PACKAGES` match with a matching exception
row is allowed but never silently dropped — it's recorded under
`exceptions_applied` in `license-report.json` for audit. Verified in a
real Ubuntu 24.04 container: an unapproved deny-listed package fails the
gate; the same package with a matching exception row passes and the
exception appears in evidence.

## What #28/#161 asks for that this pass does NOT cover

- **Cross-OSS compatibility matrix**: needs the other 5 portfolio repos
  (Narwhal, Beluga, KubeMetal, ldapium, nfs-quota-agent) to adopt the same
  vocabulary and publish comparable evidence — outside this repo's
  control or verification ability.
- **SPDX/CycloneDX interchange guidance**: `generate-sbom.sh` already
  emits both formats (via `trivy`, when installed) plus a dpkg-tsv
  fallback; a written interchange/conversion guide per #161's ask is not
  authored here.
- **Vulnerability scanning as a release gate** — `trivy` is used for SBOM
  generation only (`--offline-scan`, no vulnerability DB check wired to
  fail a build).
- **`attest`/provenance verification tooling** beyond recording the
  fields — nothing here cryptographically signs or independently
  re-verifies the provenance chain (see `docs/build-inputs.md`'s note on
  box signing being absent entirely).
- **A real Packer build exercising the new SBOM provenance fields
  end-to-end** — the field-threading was verified with `packer
  validate`/`packer fmt` and a standalone container run of
  `generate-sbom.sh` with the env vars set manually, not a full VM build
  (unlike #30's egress-restriction work, which did get a real build run).

See issue #28 (and Narwhal #161) for the full requirement list.
