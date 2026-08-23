# Build Input Inventory (#30)

External inputs consumed while building a kube-ready-box release. Everything
here is either pinned to an exact version/digest, or its floating fetch is
followed by a content check against a known-good value (marked as such
below). `tools/unpinned-input-guard.sh` runs in CI and fails a new PR that
introduces a floating download or an open-ended Packer plugin version
constraint without going through one of those two paths.

This file is maintained by hand; if you add a new external input, add a row
here in the same change.

## OS base images (ISO)

Pinned by `iso_checksum` in `packer/plugins.pkr.hcl` — Packer refuses to
proceed if the downloaded ISO doesn't match.

| Ubuntu | Arch | URL | Checksum source |
|---|---|---|---|
| 24.04.3 | amd64 | mirrors.edge.kernel.org/ubuntu-releases | `packer/plugins.pkr.hcl` `iso_data["24.04"].amd64_sum` |
| 24.04.3 | arm64 | cdimage.ubuntu.com | `packer/plugins.pkr.hcl` `iso_data["24.04"].arm64_sum` |
| 26.04 | amd64 | releases.ubuntu.com | `packer/plugins.pkr.hcl` `iso_data["26.04"].amd64_sum` |
| 26.04 | arm64 | cdimage.ubuntu.com | `packer/plugins.pkr.hcl` `iso_data["26.04"].arm64_sum` |

`tools/airgap-bundle.sh` derives its point-release from `plugins.pkr.hcl` at
runtime rather than holding an independent copy, so the two can't drift.

## Packer plugins

Pinned to exact versions in `packer/plugins.pkr.hcl`'s `required_plugins`
block (not `>=`), resolved against the versions actually installed and
tested in this repo's CI:

| Plugin | Version |
|---|---|
| virtualbox | 1.1.3 |
| vmware | 1.2.0 |
| vagrant | 1.1.6 |

Bumping any of these is a deliberate, reviewed change to the pin, not a
silent `packer init` re-resolve.

## Downloaded binaries/scripts (packer/scripts/)

| Script | What | Pin | Verification |
|---|---|---|---|
| `00-vagrant-setup.sh` | Vagrant insecure SSH pubkey | fetched from `hashicorp/vagrant@main` (floating; this key is a long-stable public constant with no versioned release to pin to) | fetched content is compared against the RSA/ED25519 key values embedded in the script; on mismatch OR fetch failure, the embedded keys are used instead — the fetch is never trusted blindly |
| `03-os-packages.sh` | `dool` (dstat replacement) | `DOOL_VERSION` (default `1.3.8`), GitHub release `.deb` | `DOOL_SHA256` checked via `sha256sum -c` before `dpkg -i` |
| `03-os-packages.sh` | `yq` (YAML processor) | `YQ_VERSION` (default `v4.44.3`) | `YQ_SHA256` (per-arch) checked via `sha256sum -c` before install; values cross-checked against yq's own `releases/<tag>/checksums` file via its `extract-checksum.sh` |
| `10-sandbox-runtime.sh` | gVisor `runsc` / `containerd-shim-runsc-v1` | `GVISOR_RELEASE` (defaults to a pinned, verified release; `latest` is accepted but logs a loud warning that it breaks reproducibility) | `.sha512` fetched from the same release origin as the binary — verifies transfer integrity, not upstream authenticity (no upstream signature to check against as of this writing) |

All four values above (`DOOL_SHA256`, `YQ_SHA256` per-arch, and the gVisor
default release) were computed by downloading the artifact directly and
running `sha256sum`/`sha512sum`, not copied from a third party.

## OS packages (apt)

Installed via `apt-get install` against Ubuntu's own signed archive
(`/etc/apt/sources.list.d/ubuntu.sources`, GPG-verified by apt itself) —
authenticity is handled by apt's existing trust chain, not by this repo.
What is **not** yet pinned: exact package *versions* — a rebuild next month
can pull newer point-releases of the same packages, so the resulting
package set is not byte-for-byte reproducible across time even though every
package is authentic. Producing a full pinned/reproducible package manifest
(e.g. an apt snapshot mirror or explicit `package=version` pins for every
installed package) is a larger follow-up, not attempted in this pass —
`packer/scripts/generate-sbom.sh` records the actually-installed versions
per build as evidence, so drift is at least visible after the fact even
though it isn't prevented before the fact.

## Not yet covered by this inventory

- Build-time network egress restriction (the requirement that builds can
  only reach required mirrors/repositories) — needs Packer/VirtualBox/VMware
  network-level policy, not just script changes; not implemented here.
- Dependency/package "cooling" and review policy for newly published
  artifacts.
- Quarantine/rollback workflow specifically for a compromised OS/package/tool
  input (distinct from `tools/release-promote.sh`'s box-level rollback,
  which operates on already-built box artifacts, not build inputs).
- A negative CI test that actually substitutes a package/binary and confirms
  the build fails closed (today's guard is static analysis of the scripts,
  not a live substitution test).

See issue #30 for the full requirement list.
