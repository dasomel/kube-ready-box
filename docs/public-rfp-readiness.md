# Public RFP Readiness Mapping (#5)

kube-ready-box is not itself an RFP product, but issue #5 asks whether it
already functions as a reproducible **Kubernetes reference OS image** for a
public-sector deployment (Narwhal/K-PaaS-style). This maps each Acceptance
Criterion in #5 to what already exists in this repo today, and states
plainly what does not.

## AC → current state

### "Ubuntu 24.04/26.04별 Kubernetes prerequisite profile 제공"

Covered. `packer/scripts/ubuntu-tuning.sh` branches by `VERSION_ID`;
`packer/plugins.pkr.hcl` builds both lines from the same template set
(`packer/*.pkr.hcl` × `var.ubuntu_version`). See
[`docs/ubuntu-2604-migration/24-04-vs-26-04-comparison.md`](ubuntu-2604-migration/24-04-vs-26-04-comparison.md)
for the concrete per-version differences (kernel, cgroup, containerd, crypto).

### "cgroup v2, containerd, kernel/sysctl, filesystem/quota preflight 자동 검사"

Covered, in two layers:

- **In-guest, at boot**: `packer/scripts/09-k8s-node-preflight.sh` installs
  `/usr/local/bin/k8s-node-preflight`, which checks cgroup v2, swap,
  `overlay`/`br_netfilter`/`iscsi_tcp` modules, `bpffs`, required sysctls,
  root filesystem type, chrony, AppArmor, auditd, CSI prerequisite
  packages, and containerd `SystemdCgroup`, emitting
  `kube-ready-node-preflight/v1` JSON.
- **Standalone, distro-neutral**: `network/`, `storage/`, `time/`,
  `security/` readiness scripts (issues #17/#18/#19/#16) cover the same
  ground plus DNS/MTU/conntrack/dual-stack, disk/inode thresholds,
  SELinux/AppArmor depth, and quota capability — runnable against any
  Ubuntu/Rocky host, aggregated by `tools/kube-ready-contracts.sh`.

Filesystem/quota specifically: `storage/node-storage-readiness.sh`'s
`quota_capability` check (added this session) reports whether
prjquota/pquota/usrquota or `xfs_quota`/`repquota` is available — detected,
not assumed.

### "CIS/Kubernetes hardening의 적용 가능 항목 목록화"

**Partially covered, not itemized.** The box already applies several
controls that map to CIS-style host hardening categories — swap disabled,
auditd installed (disabled by default per EKS/GKE/AKS convention, see
`packer/scripts/03-os-packages.sh`), AppArmor/SELinux baseline, kernel
module and sysctl enforcement, SSH key regeneration path
(`packer/scripts/98-first-boot-identity.sh`) — but there is no document
that walks the actual CIS Kubernetes Benchmark or CIS Distribution
Independent Linux Benchmark control IDs one by one and marks each
applicable/not-applicable/covered. Producing that mapping accurately
requires checking each control against the current benchmark text control
ID by control ID, which is a dedicated review pass in its own right (not
attempted here to avoid citing benchmark section numbers from memory that
could be wrong) — tracked as a follow-up, not done in this pass.

### "air-gapped 패키지 설치 검증 모드 제공"

Partially covered. `tools/airgap-bundle.sh` (issue #7) prepares an offline
build-input bundle (ISO, apt packages, Ubuntu archive keyring) and can
verify it structurally. What's not yet done: an actual verified air-gapped
*build* run (needs a real isolated network environment — see #7's own
tracking) and machine-readable evidence tying a specific air-gapped build
to a specific bundle snapshot.

### "kubelet/containerd/time-sync/DNS/network readiness 자동 리포트"

Covered. `tools/kube-ready-contracts.sh` aggregates JSON evidence from the
network/storage/time/security readiness scripts plus (when the
`RUN_ROCKY_PROFILE`/`RUN_NIXOS_PROFILE` flags are set) the Rocky/NixOS
preflight scripts, and fails closed (`evidence_missing` non-empty → exit 1)
rather than silently reporting `null` for a script that produced no
evidence — see `CLAUDE.md` mistake patterns #20/#21 for why that guarantee
exists.

### "Narwhal cluster provisioning 직전 preflight와 결과 연계"

**Not implemented — interface only.** This repo has no visibility into
Narwhal's actual provisioning pipeline or expected input format, so no real
integration exists. What Narwhal (or any external provisioner) can consume
today: `tools/kube-ready-contracts.sh`'s output is a single JSON document
with a `reports` array of per-domain evidence objects and a top-level
`evidence_missing` array; a provisioning step could run it as a
pre-flight gate and fail the run if `evidence_missing` is non-empty or any
report's `status` is `FAIL`. Building an actual Narwhal-side consumer is
out of this repo's scope until someone on that side defines the expected
call contract.

### "VM box checksum/signature 및 SBOM 메타데이터 제공"

**Half covered.** `SHA256SUMS` checksum manifests exist throughout the
release-evidence pipeline (`release-evidence/README.md`), and
`packer/scripts/generate-sbom.sh` always produces a dpkg package inventory
inside every box, plus an SPDX+CycloneDX SBOM when `trivy` is available at
build time (it deliberately runs offline-only; falls back to the dpkg
inventory alone if `trivy` isn't installed, rather than silently skipping
evidence). What does **not** exist: a
cryptographic *signature* (GPG/cosign/minisign) over the box artifact or
its SBOM — only checksums, which prove integrity against transfer
corruption but not authenticity against a trusted signer. This repo has no
signing key infrastructure today; adding one (key generation, storage,
CI signing step, public verification instructions) is a real scope of
work, not attempted in this pass.

## What this pass did NOT do

- No code changes — this is a documentation/mapping artifact only, zero
  behavioral risk.
- Did not author a CIS Benchmark control-ID-level checklist (see above —
  needs a dedicated accuracy-checked pass against the actual benchmark
  text).
- Did not implement box artifact signing.
- Did not build a real Narwhal integration (no access to Narwhal's
  interface).
- Did not run a real air-gapped build (needs an isolated network
  environment).

## Verification

This is a documentation file; "verification" here means every claim above
was checked against the actual current file contents (script line ranges,
JSON schema field names) rather than described from memory, as of the
commit this file was added in.
