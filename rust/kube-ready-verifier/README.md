# kube-ready-verifier

Optional, dependency-light Rust verifier for kube-ready-box.

## Commands

```text
kube-ready-verifier preflight [--strict-runtime] [--require-sandbox=gvisor|kata]
kube-ready-verifier verify-sha256 SHA256SUMS
kube-ready-verifier verify-evidence RELEASE_DIR
```

The CLI emits versioned JSON evidence using schema `kube-ready-evidence/v1`.
It performs no package installation and the artifact verification path does not open network connections.

`verify-evidence` structurally validates the 5 files `tools/release-promote.sh` requires
(`verification.json`, `SHA256SUMS`, `sbom.json`, `security-report.json`, `license-report.json`)
against the same rules that script's own gate uses. It is an independent cross-check, not a
replacement for `release-promote.sh`'s gate, and does not attempt signature/provenance
verification.

The initial implementation intentionally uses only the Rust standard library so the crate can be built from a vendored/offline Rust toolchain without downloading crates.

## Cross compilation

The source is Linux/Unix oriented and has no third-party dependencies. Release CI should build at minimum:

- `x86_64-unknown-linux-gnu`
- `aarch64-unknown-linux-gnu`

The runtime checks are evaluated inside the target node, not inferred from the build host.
