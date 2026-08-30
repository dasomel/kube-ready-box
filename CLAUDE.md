# CLAUDE.md - Kube Ready Box

> Compounding Engineering: 실수를 기록하고, 팀이 공유하여 같은 실수를 반복하지 않도록 합니다.

## Quick Overview

Kubernetes-ready Ubuntu 24.04 / 26.04 Vagrant Box 빌드 프로젝트. Packer를 사용해 VirtualBox/VMware용 multi-arch(AMD64/ARM64) OS 이미지 생성.

## Core Flows

| Flow | Entry Point | Key Files |
|------|-------------|-----------|
| Box Build | `packer/build.sh` | `packer/*.pkr.hcl`, `packer/scripts/` |
| OS Tuning | `packer/scripts/02-os-tuning.sh` | `packer/scripts/ubuntu-tuning.sh` |
| K8s Prereq | `packer/scripts/04-k8s-prereq.sh` | swap, modules, sysctl |
| Vagrant Cloud | `upload-boxes.sh` | `packer/scripts/upload-all.sh` |
| CI/CD | `.github/workflows/` | `build-amd64.yml`, `build-arm64.yml` |
| NixOS Box | `nixos/build.sh` | `nixos/configuration.nix`, `package-box.sh`, `upload-nixos.sh` |

## Project Structure

```
kube-ready-box/
├── packer/                     # Packer 빌드 설정
│   ├── build.sh               # 메인 빌드 스크립트
│   ├── virtualbox-*.pkr.hcl   # VirtualBox 템플릿
│   ├── vmware-*.pkr.hcl       # VMware 템플릿
│   ├── http/autoinstall-ext4/  # Cloud-init (ext4)
│   ├── http/autoinstall-xfs/   # Cloud-init (xfs)
│   ├── scripts/               # 프로비저닝 스크립트
│   └── templates/             # OVF/Vagrantfile 템플릿
├── .github/workflows/         # GitHub Actions
├── .claude/                   # Claude Code 설정
│   ├── commands/             # Slash commands
│   ├── hooks/                # Session/Edit hooks
│   └── settings.json         # 권한 및 설정
├── test-vm/                   # 빌드 테스트용
└── *.md                       # 문서
```

## Claude Code Commands

프로젝트 전용 slash commands:

| Command | Description |
|---------|-------------|
| `/build` | Packer Box 빌드 |
| `/validate` | 템플릿/스크립트 검증 |
| `/test-box` | Box 부팅 테스트 |
| `/upload` | Vagrant Cloud 업로드 |
| `/commit-push-pr` | Git 워크플로우 |
| `/add-mistake` | 실수 패턴 기록 |
| `/check` | 빠른 검증 |

## Development Commands

```bash
# Packer 초기화
cd packer && ./build.sh init

# 템플릿 검증
./build.sh validate

# 빌드 (개별)
./build.sh vmware-arm64        # VMware ARM64
./build.sh virtualbox-arm64    # VirtualBox ARM64

# 빌드 (xfs)
./build.sh vmware-arm64 --fs=xfs

# 빌드 (전체)
./build.sh all                 # ext4 4개 Box 병렬 빌드
./build.sh all --fs=xfs        # xfs 4개 Box 병렬 빌드

# 정리
./build.sh clean

# Vagrant Cloud 업로드
./upload-boxes.sh
```

## Build Matrix

| Provider | AMD64 | ARM64 | Notes |
|----------|-------|-------|-------|
| VirtualBox | O | O | VirtualBox 7.1+ (ARM64) |
| VMware | O | O | Apple Silicon 지원 |

## Key Provisioning Scripts

| Script | Purpose |
|--------|---------|
| `00-vagrant-setup.sh` | Vagrant SSH 키 설정 |
| `01-base.sh` | 패키지 업데이트 |
| `02-os-tuning.sh` | 커널 파라미터 최적화 |
| `03-os-packages.sh` | 필수 패키지 설치 |
| `04-k8s-prereq.sh` | K8s 전제조건 (swap, modules) |
| `05-disk-tuning.sh` | 디스크 I/O 최적화 |
| `06-nic-tuning.sh` | 네트워크 최적화 |
| `07-check-tuning.sh` | 튜닝 검증 |
| `99-cleanup.sh` | 빌드 정리 |

---

## Agent Routing (에이전트 라우팅)

> 모델 티어링과 팀 구성(agy-first, Sonnet 5 기본 워커, Opus 5는 아키텍처/보안/최종 승인 전용, 병렬 실행 원칙 등)은 전역 지침(`~/.claude/CLAUDE.md`)의 `routing_doctrine`/`team`을 그대로 따릅니다. 여기서는 그 규칙과 겹치지 않는, 이 저장소에만 해당하는 예외를 남깁니다.

- **4-템플릿 규칙**: pkr.hcl은 4개 provider×arch 조합(virtualbox-amd64/arm64, vmware-amd64/arm64)이 구조가 동일합니다. 하나를 수정하면 반드시 나머지 3개도 함께 반영하고 `packer validate`로 확인하세요 — 하나만 고치는 실수는 Mistake Pattern #1 참고.
- **AGENT.md**(700줄+)는 전체 로드 대신 필요한 섹션만 참조하세요.
- **PKR_VAR_\* 컨벤션**은 `docs/portfolio-contract.md`에 이미 문서화되어 있습니다 (Terraform의 TF_VAR_*와 동일한 아이디어) — 여기서 재설명하지 않습니다.

---

## Mistake Patterns (실수 패턴)

> 단일 출처는 [docs/mistakes-log.md](docs/mistakes-log.md) (23개 패턴, 스크립트/Packer/업로드/CI·CD/빌드판정/NixOS/CI검증하네스).
> 이 섹션에는 더 이상 사본을 두지 않습니다 — 두 파일에 각자 사본을 두었다가 항목이 어긋난 적이
> 있어(#31에서 통합) `AGENTS.md`/`docs/mistakes-log.md`로 옮겼습니다. 새 실수는 `/add-mistake`로
> `docs/mistakes-log.md`에 추가하세요.


---

## Permissions

### Allowed
- Packer 템플릿 수정 (*.pkr.hcl)
- 프로비저닝 스크립트 수정 (packer/scripts/)
- 문서 수정 (*.md)
- GitHub Actions 워크플로우 수정
- Claude 설정 수정 (.claude/)

### Not Allowed
- SSH 키/비밀번호 하드코딩 (var 사용)
- Box 파일 직접 수정 (.box)
- Vagrant Cloud 인증정보 노출
- 키 파일 수정 (*.pem, *.key)

---

## Team Contribution Guide

### CLAUDE.md 업데이트

코드 리뷰 시 실수 패턴 발견하면:

```
@.claude 이 실수 패턴 추가해주세요:
- 상황: ...
- 해결: ...
```

### Slash Command 추가

반복 작업이 있다면 `.claude/commands/`에 추가:

```markdown
# /command-name - 설명

## 사전 확인
\`\`\`bash
# 인라인 bash로 상태 확인
\`\`\`

## 실행 내용
...
```

### Hook 추가

자동 검증이 필요하면 `.claude/hooks/`에 추가하고 `settings.json` 업데이트

---

## Related Documentation

- [AGENT.md](.agent/AGENT.md) - 상세 기술 가이드
- [SECURITY.md](.agent/SECURITY.md) - 보안 지침
- [agent-playbook.md](docs/agent-playbook.md) - Codex 등 비-Claude 에이전트 모델/도구 라우팅
- [mistakes-log.md](docs/mistakes-log.md) - 실수 패턴 단일 출처 (23개)
- [usage.md](docs/usage.md) - Box 사용 가이드
- [k8s-post-install.md](docs/k8s-post-install.md) - K8s 설치 후 설정
- [build-inputs.md](docs/build-inputs.md) - 외부 빌드 입력 전수조사/고정 현황 (#30)
- [public-rfp-readiness.md](docs/public-rfp-readiness.md) - 공공 RFP 검증 프로파일 요구사항 대조 (#5)
- [portfolio-contract.md](docs/portfolio-contract.md) - Dasomel OSS Portfolio 공통 Make/CI/SBOM/license 계약 대조 (#28)
