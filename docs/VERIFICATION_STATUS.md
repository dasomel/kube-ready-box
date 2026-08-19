# Verification status

This document separates repository-side implementation from host-side validation that requires Vagrant/VirtualBox/VMware/KVM or real Kubernetes runtime capabilities.

| Issue | Repository implementation | Host validation remaining |
|---|---|---|
| #5 RFP profile | `test-vm/verify_box.sh --rfp-profile`, machine-readable report | Ubuntu 24.04/26.04 provider matrix and air-gapped VM run |
| #6 Node preflight | `/usr/local/bin/k8s-node-preflight` is now installed by Packer in all four Ubuntu provider/architecture templates; `test-vm/matrix.sh` | Rebuild boxes, then full Ubuntu 24.04/26.04 × amd64/arm64 × ext4/xfs × VirtualBox/VMware |
| #7 Offline inputs | `tools/airgap-bundle.sh` | Zero-egress Packer build consuming only bundle inputs |
| #8 Release | immutable promotion/rollback evidence helpers | Real Vagrant Cloud publish/download and staging matrix |
| #9 NixOS | common preflight, hardened SSH profile, flake/offline entrypoint | Nix store/cache offline build and provider smoke matrix |
| #10 SBOM/license | SPDX/CycloneDX/package inventory and license gate | Release artifact evidence and upgrade diff replay |
| #11 Sandbox | RuntimeClass, runsc handler contract, egress sample, effective/negative verifier | Real runsc/containerd E2E, resource/PID/network negative tests |
| #12 Rust | offline verifier CLI, deterministic evidence, x86_64/aarch64 build contract | Real native/ARM64 binary execution benchmark |
| #13 Conformance | node readiness attestation and aggregate evidence contracts | Real runtime/storage/time/security drift scenarios |
| #14 Identity | first-boot identity attestation, SSH regeneration/hardened profile | Two-clone, snapshot/revert, Secure Boot/TPM provider tests |
| #15 Rocky | Rocky 9/10 profile and common readiness contract | Rocky provider/arch/ext4/xfs matrix |
| #16 MAC security | AppArmor/SELinux common security evidence | Effective workload enforcement on Ubuntu/Rocky |
| #17 Network | distro-neutral network readiness schema/checks | CNI/kube-proxy/MTU/dual-stack live scenarios |
| #18 Storage | common storage readiness/evidence | NFS/iSCSI/expansion/full-disk/reboot scenarios |
| #19 Time | time readiness/evidence | NTP loss, clock drift, suspend/resume, provider-specific tests |
| #20 Observability | optional profile/evidence/limits/redaction | collection overhead and real fault-injection scenarios |

## Local validation contract

Claude Code is the verification runner for remaining host-side checks. It must not modify the repository during verification.

```bash
# Always verify the exact remote revision first
git fetch origin
git switch main
git reset --hard origin/main
git rev-parse --short HEAD

# Static checks
bash -n sandbox/verify-sandbox-evidence.sh
bash -n test-vm/matrix.sh

# VM matrix
MATRIX='vmware_desktop|test/ubuntu-24.04,virtualbox|test/ubuntu-24.04-vbox' \
  bash test-vm/matrix.sh

# Sandbox runtime verification; expected to FAIL if the requested RuntimeClass is not installed.
RUNTIME_CLASS=gvisor bash sandbox/verify-sandbox-evidence.sh
```

Validation results should be returned with the exact tested commit SHA, command, provider, architecture, filesystem, and PASS/FAIL/UNKNOWN result. Repository changes are applied here, not by the verifier.

## Current known verification finding

At revision `64cf59a`, the existing published test boxes did not contain `/usr/local/bin/k8s-node-preflight`; the VM matrix therefore correctly failed before executing the preflight checks. This was a repository packaging defect, not a hypervisor failure.

It is fixed by `6af9fe3` plus the four Packer template updates (`3ef7479`, `496b003`, `b947be3`, `e00f56d`). The boxes must be rebuilt before the matrix is rerun.

The sandbox run also correctly failed closed because the requested `gvisor` RuntimeClass was not present in the target Kubernetes cluster. That result does not prove a gVisor E2E failure; it proves the verifier detects an unavailable runtime class. A real gVisor/containerd E2E requires a cluster/node where `runsc` and the corresponding RuntimeClass are installed.
