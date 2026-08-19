# Rust Adoption Assessment

Keep Packer/HCL and shell for image construction. Rust is appropriate as a small verification/tooling layer.

Candidates: machine-readable K8s node preflight validator; offline artifact manifest/digest/signature verifier; sandbox runtime capability verifier; release evidence collector.

Do not replace Packer or NixOS configuration. Nix already provides reproducible/declarative system management.

Acceptance: amd64/arm64 cross-build, static binary, offline execution, parity with existing verification scripts, SBOM/provenance.