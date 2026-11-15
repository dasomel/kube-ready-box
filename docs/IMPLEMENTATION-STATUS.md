# Implementation Status

Last verified: 2026-11-14 against `main` (`540280b`; repository inspection only)

This is a snapshot of behavior present on the default branch, not a roadmap.

## Implemented

- Ubuntu 24.04 LTS and 26.04 LTS Kubernetes-ready base-box definitions.
- AMD64 and ARM64 build targets with VirtualBox and VMware provider coverage as documented in the build matrix.
- ext4 and XFS filesystem variants, boot-time disk extension, Kubernetes host tuning, diagnostics, security/readiness contracts, and machine-readable evidence producers.
- Optional sandbox profile assets including gVisor/runsc provisioning support, Kubernetes RuntimeClass, sandbox preflight/smoke tooling, and `kube-ready-sandbox/v1` evidence.
- Sandbox evidence distinguishes `declared`, `supported`, `effective`, and `verified`, includes negative RuntimeClass probing, and can carry upper-layer resolution/invocation correlation without becoming an authorization source.
- CI validates Packer configurations, shell/static rules, Rust verifier behavior, supply-chain controls, readiness/security contracts, and the sandbox evidence producer.
- Image identity evidence reports cloud-init residue as `WARN` (#14); node diagnostics validate limits before collection and report `UNKNOWN` when collectors are unreadable or nothing was measured (#20).
- Readiness evidence includes the storage `growroot_evidence` (#18), SELinux `selinux_relabel` (#16), certificate `cert_clock_sanity` (#19), and CNI MTU / kube-proxy capability checks (#17). Boundary and fixture tests cover chrony thresholds (#19) and Rocky preflight (#15).
- `tools/sbom-upgrade-diff.py` compares release SBOM package and license data (#10). The daily box CVE scan covers OS package databases and the allowlisted standalone binaries `yq` and gVisor components; a missing `yq` scan input is `UNKNOWN` (#98, #109).
- The containerd `SystemdCgroup` search is scoped to `/etc/containerd` in the shell attestor and Rust verifier (#120).

## Partial / environment-dependent

- Real sandbox `effective` evidence requires a Kubernetes node where the configured RuntimeClass actually starts a Pod and the runtime/security probes succeed. Mock CI validates producer control flow/schema only.
- Provider/architecture/runtime combinations that have not been exercised on a real VM remain evidence-limited even when their templates validate.

## Not claimed

- Kubernetes, a container runtime, or a CNI are not bundled as part of the standard box.
- The project does not act as an agent authorization source of truth.
- Template validation alone is not claimed as proof of real gVisor/kernel isolation.

## Evidence

- `README.md`
- `packer/`
- `sandbox/README.md`
- `sandbox/verify-sandbox-evidence.sh`
- `security/workload-security-check.sh`
- `rust/kube-ready-verifier/`
- `.github/workflows/validate.yml`
- `.github/workflows/sandbox-enforcement-evidence.yml`
- PR #39 (`8bc654e1538daa46356e56237618f5718e4529ff`)
