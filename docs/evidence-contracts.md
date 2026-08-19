# Kube-ready evidence contracts

All readiness/security/diagnostic validators emit versioned JSON rather than human-only output.

| Contract | Producer | Purpose |
|---|---|---|
| `kube-ready-evidence/v1` | Rust verifier | node preflight + offline artifact verification |
| `kube-ready-readiness/v1` | node readiness / NixOS / Rocky | Kubernetes node readiness |
| `kube-ready-sandbox/v1` | sandbox artifact tooling | sandbox runtime evidence |
| `kube-ready-security/v1` | workload security tooling | AppArmor/SELinux/security intent |
| `kube-ready-network/v1` | network profile | effective network state |
| `kube-ready-storage/v1` | storage profile | storage/backend capability |
| `kube-ready-time/v1` | time profile | clock synchronization |
| `kube-ready-observability/v1` | diagnostic profile | bounded telemetry evidence |
| `kube-ready-license/v1` | license gate | explicit license policy decision |
| `kube-ready-identity/v1` | first boot | machine identity/SSH evidence |

## Semantics

- `PASS`: the tested property was verified.
- `FAIL`: a required property was explicitly violated.
- `UNKNOWN`: the validator could not establish the property; this is never equivalent to healthy.
- `SKIP`: the check was intentionally not applicable.

A release can only claim a complete readiness result when the required profiles for its declared OS/provider/architecture/runtime/storage combination have no unresolved required `UNKNOWN` results.

Evidence should be linked to the immutable box version and SHA256 digest. Offline replay must consume supplied artifacts only and must not install packages or query external services.
