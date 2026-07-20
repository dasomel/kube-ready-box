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

## Agent Team Composition (에이전트 팀 구성)

> 모델 티어별 역할을 분리하여 비용 효율적이고 품질 높은 작업을 수행합니다.

### 역할 정의

| 역할 | 모델 | 핵심 책임 | 사용 시점 |
|------|------|-----------|-----------|
| **Architect** | Opus | 설계, 리뷰, 의사결정 | 아키텍처 변경, PR 리뷰, 복잡한 디버깅 |
| **Implementer** | Sonnet | 코드 작성, 기능 구현 | 스크립트 수정, pkr.hcl 편집, 문서 업데이트 |
| **Validator** | Haiku | 검증, 린팅, 탐색 | shellcheck, packer validate, 파일 검색 |

### 역할별 가이드라인

**Opus (Architect)**
- 복수 파일에 걸친 리팩토링 계획 수립
- 빌드 실패 원인 분석 및 해결 방향 결정
- Mistake Pattern 추가 여부 판단
- 되돌릴 수 없는 변경(버전 릴리스, 업로드) 전 검토

**Sonnet (Implementer)**
- pkr.hcl 템플릿 수정 (4개 동시 업데이트 주의)
- 프로비저닝 스크립트(packer/scripts/) 작성/수정
- GitHub Actions 워크플로우 편집
- CLAUDE.md, CHANGELOG.md 등 문서 작성

**Haiku (Validator)**
- `shellcheck packer/scripts/*.sh` 실행
- `packer validate` / `packer fmt -check` 검증
- Glob/Grep으로 파일 패턴 검색
- 단순 git 상태 확인 (git status, git diff --stat)

### 병렬 실행 패턴

독립적인 작업은 여러 에이전트를 동시에 실행하여 처리 시간 단축:

```
# 예시: 스크립트 동시 shellcheck (각각 Haiku)
Agent 1: shellcheck packer/scripts/01-base.sh
Agent 2: shellcheck packer/scripts/02-os-tuning.sh
Agent 3: shellcheck packer/scripts/03-os-packages.sh
Agent 4: shellcheck packer/scripts/04-k8s-prereq.sh
```

### 작업별 팀 패턴

| 작업 | 구성 | 흐름 |
|------|------|------|
| **새 기능 추가** | Opus → Sonnet → Haiku | 설계 → 구현 → 검증 |
| **빌드 디버깅** | Opus + Haiku | 로그 분석 → 원인 판단 → 수정 |
| **PR 리뷰** | Opus + Haiku(병렬) | Opus: 로직 리뷰, Haiku: lint/validate |
| **스크립트 리팩토링** | Opus → Sonnet → Haiku | 계획 → 4개 템플릿 수정 → shellcheck |
| **빠른 수정** | Sonnet → Haiku | 코드 수정 → 검증 |
| **릴리스** | Opus → Sonnet | 변경사항 검토 → 버전 태깅 |

### 에스컬레이션 규칙

- Haiku가 검증 실패 발견 → Sonnet에게 수정 위임
- Sonnet이 설계 판단 필요 → Opus에게 에스컬레이션
- 빌드 실패 원인 불명확 → Opus가 직접 분석

---

## Token Strategy (토큰 전략)

> 모델 선택과 컨텍스트 관리를 최적화하여 비용 대비 최대 효과를 달성합니다.

### 모델 선택 기준

| 복잡도 | 모델 | 예시 작업 | 비용 |
|--------|------|-----------|------|
| **높음** | Opus | 아키텍처 결정, 멀티파일 리팩토링, 복잡한 디버깅 | $$$ |
| **중간** | Sonnet | 코드 편집, 기능 구현, 문서 작성 | $$ |
| **낮음** | Haiku | shellcheck, lint, 파일 검색, 단순 검증 | $ |

### 판단 플로우

```
작업 수신
  ├─ 읽기 전용? (검색, 검증, lint) → Haiku
  ├─ 되돌릴 수 없는 결정? (릴리스, 아키텍처) → Opus
  ├─ 복수 파일 연쇄 수정? → 계획: Opus, 실행: Sonnet
  └─ 단일 파일 수정 → Sonnet
```

### 컨텍스트 윈도우 최적화

| 전략 | 방법 | 효과 |
|------|------|------|
| **서브에이전트 탐색** | 넓은 범위 검색은 서브에이전트에 위임 | 메인 컨텍스트 오염 방지 |
| **타겟 검색 우선** | 파일 경로를 아는 경우 Glob/Grep 직접 사용 | 불필요한 결과 제거 |
| **결과 요약 전달** | 서브에이전트 결과를 요약하여 전달 | 컨텍스트 소비 최소화 |
| **청크 분리** | 대용량 파일은 offset/limit으로 부분 로드 | 전체 파일 로딩 방지 |

**프로젝트 특화 팁:**
- pkr.hcl 4개 템플릿은 구조 유사 → 하나만 읽고 diff로 나머지 확인
- `packer/scripts/` 스크립트는 번호순 → 필요한 스크립트만 선택적 로드
- AGENT.md (700줄+)는 전체 로드 대신 섹션별 참조

### 비용 효율 패턴

**DO (권장)**
- Haiku 병렬 배치: 8개 스크립트 동시 shellcheck
- 읽기 전용 탐색은 항상 Haiku
- Opus는 최종 판단에만: Sonnet 구현 → Haiku 검증 → Opus 리뷰

**DON'T (비권장)**
- Opus로 단순 grep 실행 (→ Haiku 사용)
- Opus로 반복적 단일 파일 수정 (→ Sonnet 사용)
- 메인 컨텍스트에서 대규모 전체 파일 탐색 (→ 서브에이전트 위임)

### 핵심 규칙

1. **Haiku-First**: 의심스러우면 먼저 Haiku로 정보 수집
2. **Opus-Last**: Opus는 최종 판단과 리뷰에만 투입
3. **병렬화**: 독립 작업은 항상 동시 실행 (특히 Haiku 검증)
4. **컨텍스트 격리**: 탐색 결과는 서브에이전트 내에서 소화, 요약만 전달
5. **4-템플릿 규칙**: pkr.hcl 수정 시 반드시 4개 파일 일괄 처리

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
   - VirtualBox 7.2.4 이하: Apple Silicon에서 scancode 전송 실패
   - VirtualBox 7.2.6+: scancode 이슈 해결됨, 정상 빌드 가능
   - 해결: VirtualBox 7.2.6 이상으로 업데이트

5. **VMware Fusion 라이선스 필요**
   - 무료 버전에서 headless 빌드 실패
   - 해결: VMware Fusion Pro 또는 Player 필요

6. **0.1.0 원본 빌드 설정 임의 수정 금지**
   - 0.1.0에서 성공한 pkr.hcl 빌드 설정(boot_wait, boot_command, http_directory 등)을 임의로 수정하면 빌드 실패
   - 특별한 사정이 없는 한 원본 설정 유지
   - 수정 필요 시: `git show 327f8dc:packer/vmware-arm64.pkr.hcl` 로 원본 확인 후 신중하게 진행

7. **VMware Fusion VNC/빌드 문제 시 완전 재시작 필요**
   - VMware Fusion이 불안정하면 VNC 연결 거부, boot_command 미작동 등 발생
   - 해결: VMware Fusion 완전 재시작 (services.sh --stop/--start 포함)
   ```bash
   osascript -e 'quit app "VMware Fusion"'
   # 신버전은 services/ 하위 디렉터리 (구버전: Library/services.sh)
   sudo "/Applications/VMware Fusion.app/Contents/Library/services/services.sh" --stop
   sudo "/Applications/VMware Fusion.app/Contents/Library/services/services.sh" --start
   open -a "VMware Fusion"
   ```

### 업로드 관련

8. **버전 번호 중복**
   - 동일 버전 재업로드 시 실패
   - 해결: upload-boxes.sh의 VERSION 확인 후 실행

9. **Vagrant Cloud 인증 만료**
   - 토큰 만료 시 업로드 실패
   - 해결: `vagrant cloud auth login` 재실행

### CI/CD 관련

10. **AMD64/ARM64 워크플로우 불일치**
    - 한쪽만 수정하고 다른 쪽 누락
    - 해결: 항상 두 파일 동시 확인

### 빌드 판정 관련

11. **빌드 "실패" 판정이어도 Box 아티팩트는 정상일 수 있음**
    - VirtualBox ARM64: 최종 ISO detach 단계에서 커스텀 cleanup이 먼저 VM을 unregister해 `VBOX_E_OBJECT_NOT_FOUND` 오류 → Packer는 실패로 기록하지만 box는 이미 `output-vagrant/`에 생성됨
    - 해결: 빌드 실패 보고 시 `ls -lh packer/output-vagrant/*.box`로 아티팩트 존재/크기부터 확인 후 재빌드 판단

12. **26.04 VMware 빌드 SSH 타임아웃: 설치 후 IP 변경이 원인일 수 있음**
    - systemd 259(26.04)는 설치 후 DHCP DUID가 바뀌어 설치 단계와 다른 IP를 받음 → packer가 낡은 리스 IP만 폴링해 "Timeout waiting for SSH" (VirtualBox는 NAT 포워딩이라 무관)
    - 진단: `/var/db/vmware/vmnet-dhcpd-vmnet8.leases` 리스 갱신 여부 + Fusion 콘솔에서 `ip a`로 실제 IP 확인. 게스트가 login 프롬프트에 떠 있으면 vagrant/vagrant 로그인 → `sudo ip addr add <리스IP>/24 dev enp2s0`로 빌드 구출 가능
    - 영구 해결: autoinstall 시드 netplan에 `dhcp-identifier: mac` (두 시드 모두 적용됨)

13. **`output-vagrant/`는 빌드마다 초기화되는 공유 작업 디렉터리**
    - 다음 빌드의 패키징 단계가 디렉터리를 재생성하며 이전 빌드의 box를 삭제함 (버전/프로바이더 무관)
    - 해결: 각 빌드 완료 직후 box를 `packer/dist/` 등 별도 위치로 즉시 대피(`cp -c`). 연속/병렬 빌드 시 필수

14. **중단(kill)된 VirtualBox 빌드는 잔여 상태 2종을 남김**
    - `~/VirtualBox VMs/<name>/` 설정 파일 잔존 → 다음 빌드가 `Machine settings file already exists`로 3초 만에 실패
    - 중단 시점에 output-vagrant에 쓰다 만 **손상 box**가 남아 대피 로직이 그대로 주워갈 수 있음
    - 해결: kill 후 재빌드 전 잔여 디렉터리 삭제(+`<inaccessible>` 등록은 UUID로 unregistervm), 대피된 box는 `tar -tzf`로 무결성 검증

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
- [usage.md](docs/usage.md) - Box 사용 가이드
- [k8s-post-install.md](docs/k8s-post-install.md) - K8s 설치 후 설정
