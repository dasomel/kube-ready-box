# CLAUDE.md - Kube Ready Box

> Compounding Engineering: 실수를 기록하고, 팀이 공유하여 같은 실수를 반복하지 않도록 합니다.

## Quick Overview

Kubernetes-ready Ubuntu 24.04 Vagrant Box 빌드 프로젝트. Packer를 사용해 VirtualBox/VMware용 multi-arch(AMD64/ARM64) OS 이미지 생성.

## Core Flows

| Flow | Entry Point | Key Files |
|------|-------------|-----------|
| Box Build | `packer/build.sh` | `packer/*.pkr.hcl`, `packer/scripts/` |
| OS Tuning | `packer/scripts/02-os-tuning.sh` | `packer/scripts/ubuntu2404-tuning.sh` |
| K8s Prereq | `packer/scripts/04-k8s-prereq.sh` | swap, modules, sysctl |
| Vagrant Cloud | `upload-boxes.sh` | `packer/scripts/upload-all.sh` |
| CI/CD | `.github/workflows/` | `build-amd64.yml`, `build-arm64.yml` |

## Project Structure

```
kube-ready-box/
├── packer/                     # Packer 빌드 설정
│   ├── build.sh               # 메인 빌드 스크립트
│   ├── virtualbox-*.pkr.hcl   # VirtualBox 템플릿
│   ├── vmware-*.pkr.hcl       # VMware 템플릿
│   ├── http/autoinstall/      # Cloud-init 설정
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

# 빌드 (전체)
./build.sh all                 # 4개 Box 병렬 빌드

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

## Mistake Patterns (실수 패턴)

> Claude가 실수할 때마다 이 섹션에 추가하여 반복을 방지합니다.

### 스크립트 관련

1. **스크립트 추가 후 pkr.hcl 업데이트 누락**
   - 새 스크립트 생성 시 모든 템플릿(4개)에 provisioner 추가 필요
   - 해결: `/validate` 실행하여 확인

2. **스크립트 실행 권한 누락**
   - `chmod +x` 없이 스크립트 생성
   - 해결: 생성 후 즉시 `chmod +x` 실행

3. **스크립트 순서 의존성**
   - 01-base.sh 이전에 다른 스크립트 실행 불가
   - 해결: 번호 순서 유지

### Packer 관련

4. **ARM64 빌드 시 VirtualBox boot_command 이슈**
   - Apple Silicon에서 타이밍 문제 발생 가능
   - 해결: `boot_wait` 값 조정 (10s → 15s)

5. **VMware Fusion 라이선스 필요**
   - 무료 버전에서 headless 빌드 실패
   - 해결: VMware Fusion Pro 또는 Player 필요

### 업로드 관련

6. **버전 번호 중복**
   - 동일 버전 재업로드 시 실패
   - 해결: upload-boxes.sh의 VERSION 확인 후 실행

7. **Vagrant Cloud 인증 만료**
   - 토큰 만료 시 업로드 실패
   - 해결: `vagrant cloud auth login` 재실행

### CI/CD 관련

8. **AMD64/ARM64 워크플로우 불일치**
   - 한쪽만 수정하고 다른 쪽 누락
   - 해결: 항상 두 파일 동시 확인

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
- [usage.md](usage.md) - Box 사용 가이드
- [k8s-post-install.md](k8s-post-install.md) - K8s 설치 후 설정
