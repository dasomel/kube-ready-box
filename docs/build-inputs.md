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

## Build-time network egress restriction

`packer/scripts/00-egress-restrict.sh`, opt-in via `-var restrict_build_egress=1`
(default `0`, unrestricted — matches today's behavior). When enabled, it runs
first, before any other provisioning script, and:

1. Installs `dnsmasq` + `ipset` and points the guest's resolver at a local
   `dnsmasq` instance.
2. `dnsmasq` forwards DNS queries normally (resolving a domain isn't itself
   a risk — connecting to it is), but for each domain in its allowed list
   it also inserts the resolved IP into an `ipset`, refreshed on every
   lookup with the record's real TTL. This is deliberately *not* a
   one-time "resolve once and pin the IP" approach: GitHub/Google-fronted
   downloads sit behind CDNs whose IPs rotate, so pinning a single
   snapshot IP would make the build fail unpredictably later in the same
   run — the exact "quietly wrong, discovered late" failure mode this repo
   has spent this whole session eliminating elsewhere.
3. An `iptables` `OUTPUT` chain then allows only: loopback, established/
   related connections, DNS to the local resolver and to the two upstream
   resolvers dnsmasq forwards to, and any destination that is currently a
   member of that ipset. Everything else is dropped.
4. `packer/scripts/99-cleanup.sh` reverts all of it (removes the iptables
   chain, the ipset, `dnsmasq`, and restores the original resolver config)
   before the image is captured — a deployed node must not carry the
   build-time restriction.

The allowed-domain list lives at the top of the script and should stay in
sync with this file's tables above (Ubuntu mirrors, GitHub/githubusercontent
for the pinned release downloads, storage.googleapis.com for gVisor, and the
Korean NTP servers `01-base.sh` configures).

**What this does and does not cover, honestly:**

- The dnsmasq+ipset+iptables mechanism itself was verified directly: in a
  Linux container with `NET_ADMIN`/`NET_RAW`, a `curl` to an allowed domain
  (`raw.githubusercontent.com`) succeeded (HTTP 200, real content, and the
  ipset was populated with the CDN's actual current IPs), and a `curl` to a
  disallowed domain (`example.com`) timed out — the `DROP` rule actually
  drops traffic, this isn't just a config file that looks right.
- What was **not** verified: an actual full Packer VM build with this
  enabled end-to-end (no systemd available in the container images used
  for testing, so `systemctl enable --now dnsmasq` and the service-level
  wiring in `00-egress-restrict.sh` were not exercised — only the
  underlying firewall/DNS mechanism was, using the equivalent commands run
  directly instead of via systemd). That's why this stays opt-in
  (`restrict_build_egress` defaults to `0`) rather than becoming the
  default build behavior — flipping the default should happen only after
  someone runs a real build with it enabled and confirms nothing in
  00–99 breaks.
- The OS *installer* phase (autoinstall/subiquity, before any provisioner
  script runs) is not covered — that phase's network access is controlled
  by the ISO's own installer config, not by anything in `packer/scripts/`.

## OS package version reproducibility (apt)

Installed via `apt-get install` against Ubuntu's own signed archive
(`/etc/apt/sources.list.d/ubuntu.sources`, GPG-verified by apt itself) —
authenticity is handled by apt's existing trust chain, not by this repo.
What is **not** yet pinned: exact package *versions* — a rebuild next month
can pull newer point-releases of the same packages, so the resulting
package set is not byte-for-byte reproducible across time even though every
package is authentic. `packer/scripts/generate-sbom.sh` records the
actually-installed versions per build as evidence, so drift is at least
visible after the fact even though it isn't prevented before the fact.

Deliberately not attempted in this pass: forcing exact `apt-get install
package=version` pins repo-wide, or standing up an apt snapshot mirror
(e.g. snapshot.ubuntu.com) to install from. Both require either (a) a
"last known good" version manifest captured from an actual completed
build — which needs a real multi-provider build run to produce, not
something this environment can generate — or (b) a new external
dependency (a snapshot service) that itself becomes a build input needing
its own availability/trust evaluation. Attempting either without that
groundwork risks trading "not perfectly reproducible" for "silently
broken the next time an old package version is no longer available,"
which is a worse failure mode. Tracked as a follow-up that needs a real
build baseline first.

## Not yet covered by this inventory

- Dependency/package "cooling" and review policy for newly published
  artifacts.
- Quarantine/rollback workflow specifically for a compromised OS/package/tool
  input (distinct from `tools/release-promote.sh`'s box-level rollback,
  which operates on already-built box artifacts, not build inputs).
- A negative CI test that actually substitutes a package/binary and confirms
  the build fails closed (today's guard is static analysis of the scripts,
  not a live substitution test).

See issue #30 for the full requirement list.
