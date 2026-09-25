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
| Firewall provider/state | `network/node-network-readiness.sh` | `kube-ready-network/v1` | `firewall_backend` (`nftables` / `firewalld` / `ufw` / `UNKNOWN`), `firewall_provider`, `firewall_rules`, `firewall_state` |
| MAC (AppArmor/SELinux) | `security/workload-security-check.sh` | `kube-ready-security/v1` | `mac_backend`, `apparmor`, `apparmor_profiles`, `selinux`, `selinux_policy`, `lsm_stack` |
| seccomp/runtime | `security/workload-security-check.sh` | `kube-ready-security/v1` | `seccomp`, `seccomp_filter`, `seccomp_capability`, `runtime_probe`, `runtime_version` |

Both scripts are wired into `tools/kube-ready-contracts.sh` (reports `network`,
`security`) and run unconditionally as part of `make validate` / CI's
`contract-syntax` job. `ufw` detection in `firewall_backend` was added for #44 —
previously only `nftables`/`firewalld` were recognized. `firewall_backend` still
only reports the packet-filter *backend* (`nft` wins over `firewalld`/`ufw`
whenever it's present); `firewall_provider` names the manager that actually
owns enforcement (`firewalld`/`ufw` checked before raw `nft`) — see
`docs/evidence-contracts.md`'s network section for the full detail vocabulary.

## Distro/LSM matrix

| Distro family | MAC | Native firewall | Notes |
|---|---|---|---|
| Ubuntu / Debian / NixOS | AppArmor (`mac_backend=AppArmor`) | `nftables` (default) or `ufw` if present | Classified from `/etc/os-release` `ID`, then `ID_LIKE`; `packer/scripts/01-base.sh` pins AppArmor on Ubuntu and kube-ready-box preserves it. NixOS enablement is handled separately under D5/T-022. |
| Rocky / RHEL / Alma / Fedora / CentOS | SELinux (`mac_backend=SELinux`), required `Enforcing` | `firewalld` | Classified from `/etc/os-release` `ID`, then `ID_LIKE`; `rocky/preflight.sh` and `packer/scripts/rocky-tuning.sh` require and actively preserve SELinux `Enforcing`. |
| Other/unrecognized | `mac_backend=UNKNOWN` | `firewall_backend=UNKNOWN` | Never reported as healthy; `UNKNOWN` is a real evidence state, not a false PASS. |

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

## Cluster-installer hand-off contract

kube-ready-box is a **runtime foundation/evidence provider**, not a cluster
installer or CNI. A cluster installer consuming a kube-ready-box image must
not assume:

- Any firewall rules beyond what `firewall_backend`/`firewall_rules` evidence
  reports. kube-ready-box does not open, close, or manage ports for a CNI;
  the installer/CNI is responsible for any firewall rules its topology needs.
- A specific AppArmor profile is loaded for its workloads. Custom AppArmor
  profiles required by a workload must be distributed and loaded by that
  workload's own deployment path (e.g. a DaemonSet or node bootstrap step
  outside kube-ready-box), then verified via `apparmor_profiles` evidence.
- A specific SELinux label/`seLinuxOptions` is required or forbidden globally.
  kube-ready-box preserves whatever `Enforcing` policy the base Rocky/RHEL
  image ships; workload-specific `seLinuxOptions` remain the workload's own
  declaration, verified per-pod, never forced by a node-wide label.

The installer should instead treat `kube-ready-network/v1`/`kube-ready-security/v1`
evidence as the read-only capability inventory to gate scheduling decisions
on (e.g. refuse to schedule a workload declaring a custom AppArmor profile
onto a node where `mac_backend` isn't `AppArmor`), and must perform its own
CNI/firewall provisioning rather than relying on kube-ready-box to have done
it.

## Non-goals

- No generic firewall rule mutation outside `rocky-tuning.sh`'s existing,
  Rocky-scoped `firewalld` enable (pre-existing, not changed by #44).
- No forcing of SELinux/AppArmor state beyond what each base image already
  ships; this baseline observes and preserves, it does not toggle enforcement.
