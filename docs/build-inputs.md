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

Pinned by `iso_checksum` in `packer/plugins.pkr.hcl`'s `rocky_iso_data`
local (#15, first slice — Rocky 9, ARM64, VMware, ext4 only):

| Rocky | Arch | URL | Checksum source |
|---|---|---|---|
| 9.8 | arm64 | download.rockylinux.org/pub/rocky/9/isos/aarch64 | `packer/plugins.pkr.hcl` `rocky_iso_data["9"].arm64_sum` |

Checksum verified directly against the upstream `CHECKSUM` file at
`download.rockylinux.org/pub/rocky/9/isos/aarch64/CHECKSUM`. Rocky mirror
domains (`download.rockylinux.org`, `dl.rockylinux.org`,
`mirrors.rockylinux.org`) are in `00-egress-restrict.sh`'s
`ALLOWED_DOMAINS`, same allowlist mechanism as the Ubuntu mirrors above.

**Real boot+build confirmed** (#15): `./build.sh --os=rocky vmware-arm64`
ran end to end on this machine and produced a valid
`rocky-9-ext4-vmware-arm64.box` (~1.8GB, `tar -tzf` confirms
`Vagrantfile`/`metadata.json`/32 `disk-s*.vmdk` segments/`.vmx`/`.nvram`/
`.vmsd`/`.vmxf`, `metadata.json` reports `provider: vmware_desktop,
architecture: arm64`). The kickstart's GRUB `boot_command`
(`<up><wait>e<wait>`, `<down><down><end><wait>`,
` inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg<wait>`, `<f10>`)
worked against the real Rocky 9.8 aarch64 minimal ISO's actual GRUB2 menu
on the first attempt -- that part was never the problem.

It took four real attempts to get a clean run, and each failure was a
genuine bug caught by watching the actual VM (screen capture over the
VMware Fusion window, since `vmrun captureScreen` needs guest login that
isn't available before first boot), not a hypothesis:

1. `open-vm-tools` was listed in the kickstart's `%packages` section, but
   Rocky's *minimal* ISO doesn't carry it in its local repo -- anaconda
   stopped at an interactive "missing packages: open-vm-tools. Would you
   like to ignore this and continue with installation?" prompt with no
   way for Packer to answer it. Moved to `01-base-rocky.sh` (dnf, once
   the network is up) instead of the kickstart's offline package set.
2. The kickstart's `user --name=vagrant --groups=wheel` line never set a
   password, which normally leaves an account locked -- Packer's
   `ssh_password = "vagrant"` password auth would have had nothing valid
   to authenticate against. Added a fixed SHA-512 crypt hash for the
   conventional Vagrant `vagrant` password directly in the kickstart
   (`user ... --password=$6$... --iscrypted`), not regenerated per build,
   so the box stays reproducible.
3. `license-info.sh` unconditionally wrote to
   `/etc/update-motd.d/99-vagrant-box-info` -- that directory only exists
   because Debian/Ubuntu's `pam_motd` mechanism creates it; Rocky/RHEL
   has no equivalent, so the write failed with
   "No such file or directory" and killed the whole provisioning run.
   Branched on `command -v dpkg` (matching the pattern already used
   elsewhere in this script and in `generate-sbom.sh`/`99-cleanup.sh`):
   Ubuntu keeps the existing dynamic `/etc/update-motd.d/` script, Rocky
   writes a static `/etc/motd` instead (verified both paths in a real
   container before retrying the VM build).

Not yet done: `vagrant box add` + `vagrant up` + running
`rocky/preflight.sh` inside the booted guest to confirm it actually
reports `PASS` (plan's own verification step 7, still open). Only ext4/
VMware/ARM64/Rocky 9 has been built -- xfs, VirtualBox, AMD64, and
Rocky 10 remain untested per the plan's explicit scope.

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

- The dnsmasq+ipset+iptables mechanism was verified directly in a Linux
  container with `NET_ADMIN`/`NET_RAW` during development, then **again
  for real** in CI's `supply-chain-negative-tests` job, which runs on a
  genuine systemd VM (GitHub-hosted `ubuntu-latest`): the script's actual
  `systemctl enable --now dnsmasq` path (not a manual equivalent) brings
  the service up, `systemctl is-active dnsmasq` confirms `active`, a
  `curl` to an allowed domain succeeds (HTTP 200), a `curl` to a
  disallowed domain (`example.com`) is actually blocked, and reverting
  the restriction restores connectivity to that same domain. This job
  runs on every PR touching the relevant paths, so this stays a live
  regression check, not a one-time claim.
- **Update, real Packer build confirmed**: ran `packer build -only=virtualbox-iso.ubuntu-vbox-arm64 -var restrict_build_egress=1 -var ubuntu_version=26.04 -var filesystem=ext4` twice, end to end, on this machine. Both times `00-egress-restrict.sh` set up the restriction, every provisioning script from `00-vagrant-setup.sh` through `10-sandbox-runtime.sh` completed successfully with egress restricted (real `apt-get`/`curl` traffic to the allowed domains, including the dool/yq checksum-verified downloads), `99-cleanup.sh` reverted it ("egress restriction reverted" in both logs), and a valid `.box` was produced (`tar -tzf` confirms `metadata.json`/`Vagrantfile`/`box.ovf`/disk image, ~1.8GB). One real bug was found and fixed by this: the script ran `apt-get install` immediately as the very first provisioner, before cloud-init's own first-boot package work had released the dpkg lock, and died with `Could not get lock /var/lib/dpkg/lock-frontend` — fixed by adding the same `cloud-init status --wait || true` guard `01-base.sh` already uses.
  - Both runs also hit a `packer build` exit code of "errored" — but this is **CLAUDE.md mistake pattern #11** (VirtualBox ARM64's ISO-detach step races the local-shell packaging script's VM unregister, `VBOX_E_OBJECT_NOT_FOUND`), a pre-existing, already-documented Packer/VirtualBox interaction with no relation to this script — confirmed unrelated by reproducing it identically on both the restricted-egress run and by it being pattern #11's known, generic behavior. The box artifact was valid both times regardless of Packer's reported exit code, per that pattern's own documented remedy (check `output-vagrant/*.box` directly rather than trust the reported exit code).
  - Still not covered: the other 7 provider/arch/OS/filesystem combinations (only virtualbox-arm64 × 26.04 × ext4 was run), and VMware specifically (untested with this option). `restrict_build_egress` stays opt-in (default `0`) until more combinations are confirmed — one verified target doesn't retire the "verify the rest before flipping the default" caveat, it just means the mechanism itself is no longer hypothetical.
- **VMware attempt — inconclusive, not a failure of this feature**: tried `packer build -only=vmware-iso.ubuntu-vmware-arm64 -var restrict_build_egress=1 -var ubuntu_version=26.04 -var filesystem=ext4` on this machine while 4 unrelated VMware VMs from another local project were already running and heavily using the same disk (individual guest NVMe writes were taking 1.5s+ each, confirmed via the build VM's own `vmware.log`). The base Ubuntu autoinstall never finished booting to SSH within the template's 2h `ssh_timeout` and Packer tore the VM down — `00-egress-restrict.sh` (or any provisioner script) never got a chance to run, since that only happens after SSH becomes available. This result says nothing about whether the egress mechanism works on VMware; it needs a retry on an otherwise-idle host before it counts as covered either way.
- The OS *installer* phase (autoinstall/subiquity, before any provisioner
  script runs) is not covered — that phase's network access is controlled
  by the ISO's own installer config, not by anything in `packer/scripts/`.

## Negative tests (CI)

`supply-chain-negative-tests` in `.github/workflows/validate.yml` runs on
every relevant PR:

- the egress-restriction live test described above
- a mismatched-checksum test against the real `03-os-packages.sh`: it
  overrides `DOOL_SHA256` to a value that won't match the real download,
  runs the actual script, and asserts both that it exits non-zero *and*
  that `/usr/local/bin/dool` was never installed — fail-closed, not just
  fail-noisy

This is #30's "negative test covers substituted package/binary and
unexpected network access" acceptance criterion, satisfied for these two
specific cases (checksum substitution, network egress) — not a general
fuzzer covering every input in the tables above.

## Not yet covered by this inventory

- Dependency/package "cooling" and review policy for newly published
  artifacts.
- Quarantine/rollback workflow specifically for a compromised OS/package/tool
  input (distinct from `tools/release-promote.sh`'s box-level rollback,
  which operates on already-built box artifacts, not build inputs).
- Negative tests for the other pinned downloads (yq, gVisor) and for the
  Packer plugin pins — only dool has a live substitution test today.
- A real Packer-orchestrated build with `restrict_build_egress=1`.

See issue #30 for the full requirement list.
