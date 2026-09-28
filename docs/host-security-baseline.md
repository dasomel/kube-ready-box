# Host security baseline (#44)

Read-only inventory of firewall provider/state, mandatory access control (MAC),
and seccomp/container-runtime prerequisites, per distro family. This document
covers **what kube-ready-box observes and preserves**, not a firewall/MAC
policy kube-ready-box enforces on the guest's behalf.

## Evidence producers

No new schema was introduced: the signal #44 asks for was already split across
two existing read-only validators, registered in `docs/evidence-contracts.md`.

| Property | Producer | Schema | Checks |
|---|---|---|---|
| Firewall provider/state | `network/node-network-readiness.sh` | `kube-ready-network/v1` | `firewall_backend` (`nftables` / `firewalld` / `ufw` / `UNKNOWN`), `firewall_provider`, `firewall_rules`, `firewall_state`, `egress_chain_removed` (build-only `KUBE_READY_EGRESS` chain stayed removed, #44 REQ-007/T-016) |
| MAC (AppArmor/SELinux) | `security/workload-security-check.sh` | `kube-ready-security/v1` | `mac_backend`, `apparmor`, `apparmor_profiles`, `selinux`, `selinux_policy`, `lsm_stack` |
| seccomp/runtime | `security/workload-security-check.sh` | `kube-ready-security/v1` | `seccomp`, `seccomp_filter`, `seccomp_capability`, `runtime_probe`, `runtime_version` |

A disabled AppArmor or a permissive/disabled SELinux on its native, capable host is `FAIL`,
never `PASS` and never the generic `UNKNOWN` used for "cannot determine" — unconditionally,
regardless of `KUBE_READY_SECURITY_PROFILE` or any other input (#44 D4). See
`docs/evidence-contracts.md`'s reclassification section for the full PASS/FAIL/UNKNOWN mapping
per check.

Both scripts are wired into `tools/kube-ready-contracts.sh` (reports `network`,
`security`) and run unconditionally as part of `make validate` / CI's
`contract-syntax` job. `ufw` detection in `firewall_backend` was added for #44 —
previously only `nftables`/`firewalld` were recognized. `firewall_backend` still
only reports the packet-filter *backend* (`nft` wins over `firewalld`/`ufw`
whenever it's present); `firewall_provider` names the manager that actually
owns enforcement (`firewalld`/`ufw` checked before raw `nft`) — see
`docs/evidence-contracts.md`'s network section for the full detail vocabulary.

## OS/LSM matrix

| Image | Native LSM (preserved) | Firewall as shipped |
|---|---|---|
| Ubuntu 24.04 (default) / 26.04 | **AppArmor**: kept enabled via `packer/scripts/01-base.sh`; disabled-on-capable-kernel is `FAIL` (D4) | No policy from kube-ready-box. Distro default `ufw` is installed but inactive (confirmed on a built ARM64/VMware box, #44 T-002: `ufw status` = `Status: inactive`) |
| Rocky 9 | **SELinux `Enforcing`**: required and actively preserved by `packer/http/rocky-9-*/ks.cfg` and `packer/scripts/rocky-tuning.sh` | **`firewalld` active with SSH allowed, preserved intentionally** (#44 D8) — the build only *adds* the `ssh` service; it does not remove or verify other default-zone services/ports, so exclusivity to SSH is not claimed. Confirmed on a built ARM64/VMware box (#44 T-002): `firewall-cmd --state`=`running`; runtime and permanent active zone `public`; both list `cockpit dhcpv6-client ssh`, no explicit ports, no rich rules |
| Rocky 10 | Reserved, rejected by `packer validate` until built | N/A |
| NixOS | AppArmor, **enabled** (#44 D5/T-022): `security.apparmor.enable = true`; KVM VM test verifies enabled and disabled states plus containerd AppArmor workload enforcement. Docker containers remain unconfined by AppArmor on NixOS (#63); `apparmor=PASS` reports host LSM state and does not assert Docker workload confinement | Disabled by design (`nixos/configuration.nix`: "K8s CNI manages iptables/nftables") |
| Debian / RHEL / Alma / Fedora / CentOS (bring-your-own host running the validators, not built here) | Classified from `/etc/os-release` `ID`, then `ID_LIKE`: Debian → AppArmor; RHEL/Alma/Fedora/CentOS → SELinux `Enforcing` required | Classified, never configured |
| Other/unrecognized | `mac_backend=UNKNOWN` | `firewall_backend=UNKNOWN` |

`UNKNOWN` is a real evidence state, not a false `PASS` — an unrecognized OS family or an
unreadable kernel/proc value is never reported healthy.

## Blind-mutation guard (#44 C-15/REQ-007)

`tools/host-mutation-guard.sh` statically fails `make lint`/CI on any
`iptables`/`nft`/`ufw`/`firewall-cmd`/`setenforce`/`aa-disable`/apparmor-disabling
`systemctl`/declarative-NixOS-disable form outside a per-line allowlist
(`rocky-tuning.sh`, the Rocky kickstarts, `00-egress-restrict.sh`,
`99-cleanup.sh`, `nixos/configuration.nix`'s one documented firewall-disable
line). It scans shell, Nix, Kickstart, HCL, Rust, YAML and `.conf` sources
under the tracked tree, but **not `.github/workflows/`**: a workflow's
`run:` steps execute on the ephemeral GitHub Actions runner, never on a
kube-ready-box image, so a negative-test job there (e.g. `validate.yml`'s
`iptables -D/-F/-X` teardown of a *test* egress chain) is CI test infra, not
the host-image mutation this guard exists to catch.

## Seccomp/runtime prerequisites

`security/workload-security-check.sh` verifies, per node:
- `seccomp`: kernel interface present (`/proc/self/status` reports `Seccomp:`).
- `seccomp_filter`: filter-mode support from the `Seccomp_filters` proc-status field or, on older kernels, `errno` and `kill_process` in `actions_avail`; a known Linux kernel without either signal reports `FAIL`.
- `seccomp_capability`: available seccomp actions (`/proc/sys/kernel/seccomp/actions_avail`).
- `runtime_probe` / `runtime_version`: a CRI tool (`crictl` or `containerd`/`ctr`) is present and reports a version.

These are node-level prerequisites only; actual per-pod seccomp profile
effectiveness must be verified against a running workload, not a node-only
image (see `security/README.md`'s `declared → supported → loaded → effective →
verified` contract).

## Cluster-installer hand-off contract (#44 REQ-008/AC-007)

kube-ready-box is a **runtime foundation/evidence provider**, not a cluster
installer or CNI. For each area below: what the image guarantees, what the
installer/cluster operator must provide, how to verify it, and what rollback
looks like. The installer should treat `kube-ready-network/v1`/
`kube-ready-security/v1` evidence as a read-only capability inventory to gate
scheduling decisions on, and must perform its own CNI/firewall/runtime
provisioning rather than relying on kube-ready-box to have done it.

### Host firewall / ports

- **Image guarantees**: Ubuntu ships `ufw` installed but inactive, no policy
  applied (confirmed #44 T-002). Rocky 9 ships `firewalld` active with the
  `ssh` service allowed, **preserved intentionally, not exclusively
  ssh-only** (#44 D8) — other default-zone services/ports are neither removed
  nor proven absent by the build. NixOS ships with its firewall disabled by
  design. kube-ready-box never opens, closes, or generates a firewall policy
  for any Kubernetes/CNI port on any image (D1).
- **Installer obligation**: determine and apply the firewall rules its actual
  cluster topology and CNI require (e.g. `6443`/`10250`/CNI overlay ports).
  Rocky ships `firewalld` active in the `public` zone with only its default
  services (`cockpit dhcpv6-client ssh` as observed in T-002), so ports such
  as these are not open until the installer opens them (D8). Stage changes audit→enforce, keep an out-of-band
  console available, and snapshot the existing ruleset before mutating it.
- **Verification**: `bash network/node-network-readiness.sh | jq '.checks[] | select(.id | test("firewall|egress"))'`
  reports `firewall_provider`, `firewall_state`, `firewall_rules` for the
  owning manager (`firewalld`/`ufw`/`nftables`/`external`/`none`) and
  `egress_chain_removed` (confirms no build-time egress chain survived). See
  `docs/evidence-contracts.md`'s network section for the full detail
  vocabulary.
- **Rollback**: the installer reverts to its own pre-change ruleset snapshot;
  kube-ready-box's shipped state (Ubuntu/NixOS: no policy; Rocky: SSH-allowed
  `firewalld`) is never touched by this hand-off and needs no rollback on the
  image side.

### containerd AppArmor/SELinux integration

- **Image guarantees**: containerd is not installed in the Ubuntu or Rocky
  base box, so there is no runtime LSM integration to verify at image level
  for those two images (C-12, N/A). On NixOS, T-022 verifies a containerd
  workload is confined by an AppArmor profile. Docker is also enabled in the
  image but its AppArmor integration is currently ineffective: Docker-launched
  workloads run `unconfined` even when Docker reports AppArmor support (#63).
  The host-level `apparmor` check reports kernel state only; it is not evidence
  of Docker workload confinement.
- **Installer obligation**: wherever the installer supplies containerd (or
  another CRI runtime), it must configure and verify that runtime's AppArmor
  default-profile (Ubuntu-family) or `enable_selinux`/`container-selinux`
  (Rocky/RHEL-family) integration itself; this is outside kube-ready-box's
  scope.
- **Verification**: node-level `mac_backend`/`apparmor`/`selinux` evidence
  from `security/workload-security-check.sh` confirms the node's native LSM
  is enforcing, which the installer's runtime integration then builds on; the
  installer's own runtime config/tests must confirm the integration itself.
- **Rollback**: the installer's own runtime configuration rollback; not a
  kube-ready-box concern.

### Custom AppArmor profile distribution

- **Image guarantees**: none. kube-ready-box does not ship or load any
  workload-specific AppArmor profile.
- **Installer obligation**: distribute and load custom AppArmor profiles
  required by a workload through that workload's own deployment path (e.g. a
  DaemonSet or node bootstrap step outside kube-ready-box), then confirm the
  profile is present before scheduling onto the node.
- **Verification**: `aa-status --json` (or the plain-text fallback) for the
  profile name, matching how `security/workload-security-check.sh`'s
  `apparmor_profiles` check itself parses `aa-status` output. Gate scheduling
  a workload that declares a custom profile on `mac_backend=AppArmor` first.
- **Rollback**: remove/reload the profile via the same workload deployment
  path that installed it; kube-ready-box holds no state to roll back.

### `seLinuxOptions`

- **Image guarantees**: Rocky preserves whatever `Enforcing` SELinux policy
  the base image ships (`selinux=PASS Enforcing`, `selinux_policy` checks both
  forward drift — config wants enforcing, runtime does not — and reverse
  drift — config no longer wants enforcing while the runtime is still
  `Enforcing`). kube-ready-box never sets or forbids a workload-scoped
  `seLinuxOptions` label.
- **Installer obligation**: apply workload-scoped `seLinuxOptions` in the pod
  spec where required, and gate deployment on the node's `selinux`/
  `selinux_policy` evidence rather than assuming a label.
- **Verification**: `bash security/workload-security-check.sh` for
  `selinux`/`selinux_policy`/`mac_backend`; `kubectl get pod <pod> -o
  jsonpath='{.spec.securityContext.seLinuxOptions}'` for the pod's own
  declared value.
- **Rollback**: revert the workload's `seLinuxOptions` in its own manifest;
  the node's SELinux enforcement state is unaffected either way.

### seccomp `RuntimeDefault`

- **Image guarantees**: node-level prerequisites only —
  `security/workload-security-check.sh` reports `seccomp` (kernel interface
  present), `seccomp_capability` (available actions), and `seccomp_filter`
  (filter-mode support; `FAIL` on a known kernel that lacks it). Effective
  per-pod `RuntimeDefault` cannot be proven from a node-only image.
- **Installer obligation**: run workloads with `seccompProfile.type:
  RuntimeDefault` (or stricter) and verify the pod actually applies it — a
  node reporting `seccomp_filter=PASS` is necessary but not sufficient.
- **Verification**: `bash security/workload-security-check.sh` for the node
  prerequisites; `sandbox/verify-sandbox-evidence.sh`'s `seccompNoNewPrivs`
  check for pod-level proof, which requires `Seccomp: 2` in
  `/proc/self/status` inside the pod (#44 T-017 — a pod stuck at mode `1` is
  `FAIL`, not `PASS`).
- **Rollback**: revert the workload's `seccompProfile` in its own manifest.

### Exceptions (#44 REQ-009)

An exception (for example, a host that genuinely cannot run a firewall, or a
recorded, time-bound carve-out for a disabled LSM) must be recorded as
evidence with an **owner**, a **reason**, and an **expiry**, never as a
suppressed `PASS`. An exception missing any of those three fields, or past
its expiry, is treated as no exception at all: the underlying check reports
its normal `FAIL`/`UNKNOWN`. There is no `KUBE_READY_SECURITY_PROFILE` (or
other) input that suppresses a disabled/permissive native LSM to `PASS` or
`UNKNOWN` (D4). A valid REQ-009 exception documents an accepted deviation
next to the evidence; it does not change the check result. The only way to
change the result itself is to fix the host or revert the reclassification
commit. As of this writing, no host-security-specific exception file
ships in this repository (compare `tools/sbom-license-gate.sh`'s
`etc/license-exceptions.tsv` for the owner/reason pattern used elsewhere);
record exceptions in the PR/issue that requests them until one exists.

## Non-goals

- No generic firewall rule mutation outside `rocky-tuning.sh`'s existing,
  Rocky-scoped `firewalld` enable (pre-existing, not changed by #44).
- No forcing of SELinux/AppArmor state beyond what each base image already
  ships; this baseline observes and preserves, it does not toggle enforcement.
