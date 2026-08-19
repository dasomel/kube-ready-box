# Rust Adoption Assessment

kube-ready-box should remain Packer/HCL + shell for image construction. Rust is useful as a small verification/tooling layer, not as a replacement for Packer.

## Medium/high candidates

- preflight validator: kernel/cgroup/modules/runtime/security checks with typed machine-readable output
- offline artifact manifest verifier: digest/checksum/signature/SBOM validation
- sandbox runtime verifier: gVisor/Kata capability and RuntimeClass preflight
- release evidence collector: normalize test results into one immutable JSON report

## Keep existing tooling

- Packer templates and provider-specific provisioning
- cloud-init/autoinstall shell where existing ecosystem support is stronger
- NixOS configuration itself; Nix already provides declarative/reproducible system management

## Validation

- cross compile amd64/arm64
- static single-binary distribution
- offline build
- parity against existing shell verification
- no dependency on network at verification runtime
