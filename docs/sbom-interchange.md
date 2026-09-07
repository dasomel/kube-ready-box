# SBOM Interchange Guide (#28 / Narwhal #161)

How to pull kube-ready-box's SBOM out of a built box and load it into common
SPDX/CycloneDX consumers. Written from the real generator
(`packer/scripts/generate-sbom.sh`) and the real release pipeline
(`tools/sbom-license-gate.sh`, `tools/release-promote.sh`); it does not
describe anything not already in this repo. See `docs/portfolio-contract.md`
("SBOM metadata") for the field-provenance table this guide builds on.

## What the box carries

`generate-sbom.sh` runs **inside the guest** during a real Packer build and
writes everything under `/etc/vagrant-box/`:

| File | Content |
|---|---|
| `manifest.json` | `schema_version: 3` provenance record (artifact/source/supplier/license/build_id/commit_sha/workflow_run/architecture/timestamp) |
| `sbom-spdx.json` | Trivy `spdx-json` output, only if `trivy` is present in the guest |
| `sbom-cyclonedx.json` | Trivy `cyclonedx` output, only if `trivy` is present in the guest |
| `packages.txt` | `dpkg-query`/`rpm -qa` flat inventory (always produced, trivy or not) |
| `components.tsv` | Same inventory, name/version/arch only |
| `kernel-modules-firmware.tsv` | Kernel version + `/lib/modules`, `/lib/firmware` file listing |
| `inventory-SHA256SUMS` | `sha256sum` of `packages.txt`, `components.tsv`, `kernel-modules-firmware.tsv` |

Trivy is **not installed by this repo's scripts** and is not version-pinned
where it is installed — build logs under `packer/logs/` show trivy 0.69.1,
0.71.0 and 0.72.0 across different real builds, and several builds simply
log `trivy not installed; generating deterministic dpkg inventory only` and
skip the two SBOM-format files entirely. `manifest.json`'s
`sbom_generator` field always records which case applied
(`trivy version --format json` output, or the literal string
`offline-dpkg-inventory`) — check that field before assuming
`sbom-spdx.json`/`sbom-cyclonedx.json` exist on a given box.

## Spec versions actually emitted

Reproduced locally (`ubuntu:24.04` container, trivy installed via the
upstream install script, `generate-sbom.sh` run with the provenance env vars
set — see Verification below) with **trivy 0.74.0**:

- `sbom-spdx.json`: `"spdxVersion": "SPDX-2.3"`, `"dataLicense": "CC0-1.0"`, creator `"Tool: trivy-0.74.0"`.
- `sbom-cyclonedx.json`: `"bomFormat": "CycloneDX"`, `"specVersion": "1.7"`, `"$schema": "http://cyclonedx.org/schema/bom-1.7.schema.json"`.

Because trivy is unpinned, **the exact spec version is whatever the
installed trivy release emits at build time** — a box built with trivy
0.69.1 will not necessarily carry the same `specVersion`/`spdxVersion` as
one built with 0.74.0. Treat the two numbers above as illustrative, not a
repo-wide guarantee; `manifest.json`'s `sbom_generator` field is the
authoritative per-box source of the trivy version actually used.

## Extracting SBOM from a built box

Same `vagrant ssh -c` pattern already used elsewhere in this repo
(`docs/usage.md`):

```bash
vagrant ssh -c "cat /etc/vagrant-box/manifest.json"
vagrant ssh -c "cat /etc/vagrant-box/sbom-spdx.json" > sbom-spdx.json
vagrant ssh -c "cat /etc/vagrant-box/sbom-cyclonedx.json" > sbom-cyclonedx.json
```

Or, against a mounted/extracted box image rather than a running VM, run the
same tooling `sbom-license-gate.sh` uses for `ROOT=`:

```bash
ROOT=/path/to/mounted-image tools/sbom-license-gate.sh
```

## Joining SBOM to the box digest (`build_id`)

`manifest.json` is written **inside the guest before the box is packaged**,
so it cannot contain the box artifact's own checksum — there's no digest to
record yet at that point (`docs/portfolio-contract.md` explains this in
full). The digest lives separately, in `release-evidence/$VERSION/SHA256SUMS`,
produced after packaging. The two are linked by `provenance.build_id` in
`manifest.json`, which is the same `build_id` (`PKR_VAR_build_id`,
`${GITHUB_RUN_ID:-local}-<timestamp>`) threaded by `packer/build.sh` into
that release's evidence set — match `manifest.json`'s `build_id` against the
`release-evidence/$VERSION/` directory that was produced by the same build
run, not by filename convention.

Note the naming mismatch this implies: `tools/release-promote.sh` requires
a file literally named `sbom.json` under `release-evidence/$VERSION/`
(`EVIDENCE_FILES="verification.json SHA256SUMS sbom.json security-report.json license-report.json"`),
but `generate-sbom.sh` produces `manifest.json` + `sbom-spdx.json` +
`sbom-cyclonedx.json` inside the guest — there is no script in this repo
that copies or renames the guest output into `release-evidence/$VERSION/sbom.json`.
That copy/rename step is a manual gap today (see "Known gaps" below).

## Loading into common consumers

**syft / grype** (either format; CycloneDX shown, SPDX works the same way):

```bash
grype sbom:sbom-cyclonedx.json
grype sbom:sbom-spdx.json
syft convert sbom-spdx.json -o cyclonedx-json=converted.cdx.json
```

**Dependency-Track** (CycloneDX upload API; swap in a real project UUID/API key):

```bash
curl -X POST "https://<dtrack-host>/api/v1/bom" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -F "project=<project-uuid>" \
  -F "bom=@sbom-cyclonedx.json"
```

**cyclonedx-cli validate** (this is the exact command run in Verification below):

```bash
docker run --rm -v "$PWD:/d" cyclonedx/cyclonedx-cli validate --input-file /d/sbom-cyclonedx.json
```

**SPDX validation** (`spdx-tools`'s `pyspdxtools` entry point):

```bash
pip install spdx-tools
pyspdxtools -i sbom-spdx.json -o converted.spdx.json
```

## Known gaps

- **No `digest` field in `manifest.json`** — by design; see the join-key
  section above. Trivy's inventory checksums cover individual OS packages,
  not the `.box` artifact.
- **SBOM is not CI-gated.** The PR gate (`validate.yml`) never runs
  `generate-sbom.sh` — it only runs during a real Packer build, which
  `validate.yml` deliberately skips (too slow/heavy). A PR can merge with
  no SBOM regenerated at all.
- **No signing.** Nothing in this repo signs `manifest.json`,
  `sbom-spdx.json`, `sbom-cyclonedx.json`, or `SHA256SUMS` — no
  cosign/in-toto/Sigstore step anywhere (`docs/portfolio-contract.md` notes
  the same gap for provenance generally).
- **`release-evidence/$VERSION/sbom.json` has no producer script.** An
  operator following `docs/DEPLOY_CHECKLIST.md` today must manually place a
  file there before `tools/release-promote.sh promote` accepts the
  evidence set; which of the three guest SBOM files (or a merge) belongs
  there is not decided by any script in this repo.
- **Trivy install is unpinned** where it happens at all, so
  `spdxVersion`/`specVersion` can drift between builds; some real builds
  have no trivy and produce only the dpkg-tsv fallback.

## Verification

Ran for real in a disposable `ubuntu:24.04` container (`docker run --rm -v
"$PWD:/w" -w /w ubuntu:24.04 ...`, not a real guest):

- Installed trivy via the upstream install script (resolved to 0.74.0),
  then ran `packer/scripts/generate-sbom.sh` with the same provenance env
  vars `packer/build.sh` sets in a real build. Produced real
  `manifest.json` (`schema_version: 3`, 113 packages), `sbom-spdx.json`
  (SPDX-2.3), and `sbom-cyclonedx.json` (CycloneDX 1.7).
- Validated CycloneDX: `docker run --rm -v <dir>:/d cyclonedx/cyclonedx-cli
  validate --input-file /d/sbom-cyclonedx.json` → `BOM validated
  successfully.`
- Validated SPDX: `pip install spdx-tools` (provides `pyspdxtools`) then
  `pyspdxtools -i sbom-spdx.json -o converted.spdx.json` → exit 0, no
  validation errors, round-tripped to JSON cleanly.
- **Not verified**: the `vagrant ssh -c` extraction commands (no running
  box VM here — they follow the pattern already used in `docs/usage.md`
  for `/etc/vagrant-box/info.json`). The Dependency-Track command is a
  standard API call, not run against a real server. The missing
  `release-evidence/$VERSION/sbom.json` producer script is a
  repo-inspection finding, not reproduced.
