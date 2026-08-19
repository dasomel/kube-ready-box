# Verification status

This document separates repository-side implementation from host-side validation that requires Vagrant/VirtualBox/VMware/KVM or real Kubernetes runtime capabilities.

| Issue | Repository implementation | Host validation remaining |
|---|---|---|
| #5 RFP profile | `test-vm/verify_box.sh --rfp-profile`, machine-readable report | Ubuntu 24.04/26.04 provider matrix and air-gapped VM run |
| #6 Node preflight | `/usr/local/bin/k8s-node-preflight`, `test-vm/matrix.sh` | Full Ubuntu 24.04/26.04 × amd64/arm64 × ext4/xfs × VirtualBox/VMware |
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

Claude Code is the verification runner for the remaining host-side checks. It must not modify the repository during verification.

```bash
# Single case
PROVIDER=vmware_desktop BOX=test/ubuntu-24.04 bash test-vm/matrix.sh

# Multiple cases
MATRIX='vmware_desktop|test/ubuntu-24.04,virtualbox|test/ubuntu-24.04-vbox' \
bash test-vm/matrix.sh

# Sandbox runtime verification
RUNTIME_CLASS=gvisor bash sandbox/verify-sandbox-evidence.sh
```

Validation results should be returned with the exact tested commit SHA, command, provider, architecture, filesystem, and PASS/FAIL/UNKNOWN result. Repository changes are applied here, not by the verifier.
