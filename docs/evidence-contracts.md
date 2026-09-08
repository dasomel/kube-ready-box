# Kube-ready evidence contracts

All readiness/security/diagnostic validators emit versioned JSON rather than human-only output.

| Contract | Producer | Purpose |
|---|---|---|
| `kube-ready-evidence/v1` | Rust verifier | node preflight + offline artifact verification |
| `kube-ready-readiness/v1` | node readiness / NixOS / Rocky | Kubernetes node readiness |
| `kube-ready-sandbox/v1` | sandbox artifact tooling | sandbox runtime/effective-enforcement evidence |
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

## Enforcement provider boundary

`kube-ready-box` is an **enforcement/evidence provider**, not an agent authorization source of truth. In particular, `kube-ready-sandbox/v1` separates these states:

```text
declared -> supported -> effective -> verified
```

- `declared`: the requested RuntimeClass exists and names a handler.
- `supported`: the handler is one of the explicitly recognized sandbox runtime families.
- `effective`: a workload using that RuntimeClass actually reaches a running container/runtime instance.
- `verified`: effective runtime evidence is accompanied by the required security/resource checks and negative enforcement probe.

The sandbox evidence producer may receive `RESOLUTION_ID` and `INVOCATION_DIGEST` from an upper execution-security layer. They are copied into `correlation` with `authoritySemantics: none-correlation-only`; their presence never authorizes execution and kube-ready-box does not recompute an upstream policy decision.

Each emitted sandbox record also includes `evidenceDigest`, a SHA-256 digest over the canonical JSON evidence object before the digest field is added. Consumers can therefore bind the effective enforcement result to their own decision/invocation chain without making this node image the policy authority.

The `missing-runtime-class` negative probe demonstrates the Kubernetes/runtime enforcement boundary. It explicitly does **not** prove that an upstream request was correctly authorized or denied; request-side authorization must be tested separately by the agent/control-plane repository.
