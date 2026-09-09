# 구현 상태

Last verified: 2026-09-09 against `main`

이 문서는 default branch에 실제 존재하는 동작의 snapshot이며 roadmap이 아닙니다.

## 구현됨

- Ubuntu 24.04 LTS / 26.04 LTS Kubernetes-ready base box 정의.
- AMD64/ARM64 build target 및 문서화된 VirtualBox/VMware provider coverage.
- ext4/XFS variant, boot-time disk extension, Kubernetes host tuning, diagnostics, security/readiness contract와 machine-readable evidence producer.
- gVisor/runsc provisioning support, Kubernetes RuntimeClass, sandbox preflight/smoke tooling 및 `kube-ready-sandbox/v1` evidence를 포함한 optional sandbox profile 자산.
- Sandbox evidence의 `declared`, `supported`, `effective`, `verified` 분리, negative RuntimeClass probe, authorization source가 되지 않는 correlation-only resolution/invocation metadata.
- Packer, shell/static rules, Rust verifier, supply-chain, readiness/security contract와 sandbox evidence producer를 검증하는 CI.

## 부분적 / 환경 의존

- 실제 sandbox `effective` evidence는 configured RuntimeClass Pod가 실제 Kubernetes node에서 실행되고 runtime/security probe를 통과해야 합니다. Mock CI는 producer control flow/schema만 검증합니다.
- 실제 VM에서 실행되지 않은 provider/architecture/runtime 조합은 template validation이 성공해도 runtime evidence가 제한적입니다.

## 주장하지 않음

- 표준 box에 Kubernetes/container runtime/CNI를 포함하지 않습니다.
- Agent authorization source of truth 역할을 하지 않습니다.
- Template validation만으로 실제 gVisor/kernel isolation을 증명했다고 주장하지 않습니다.

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
