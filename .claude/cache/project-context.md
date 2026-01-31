# Project Context Cache - Kube Ready Box

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kube Ready Box Build                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐  │
│  │   Packer    │────>│  Provisioner │────>│   Vagrant Box   │  │
│  │  Template   │     │   Scripts    │     │   (.box file)   │  │
│  │  (*.pkr.hcl)│     │  (scripts/*) │     │                 │  │
│  └─────────────┘     └──────────────┘     └─────────────────┘  │
│        │                    │                      │            │
│        v                    v                      v            │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    Build Matrix                            │ │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐           │ │
│  │  │ VirtualBox │  │ VirtualBox │  │   VMware   │  ...      │ │
│  │  │   AMD64    │  │   ARM64    │  │   ARM64    │           │ │
│  │  └────────────┘  └────────────┘  └────────────┘           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                             │                                   │
│                             v                                   │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    Vagrant Cloud                          │ │
│  │            dasomel/ubuntu-24.04 (4 providers)            │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Key Entry Points

| Category | File | Description |
|----------|------|-------------|
| Build Entry | `packer/build.sh` | 모든 빌드 작업의 진입점 |
| VBox AMD64 | `packer/virtualbox-amd64.pkr.hcl` | VirtualBox x86 템플릿 |
| VBox ARM64 | `packer/virtualbox-arm64.pkr.hcl` | VirtualBox ARM 템플릿 |
| VMware AMD64 | `packer/vmware-amd64.pkr.hcl` | VMware x86 템플릿 |
| VMware ARM64 | `packer/vmware-arm64.pkr.hcl` | VMware ARM 템플릿 |
| Cloud-init | `packer/http/autoinstall/user-data` | 자동 설치 설정 |
| Upload | `upload-boxes.sh` | Vagrant Cloud 업로드 |

## Common Patterns

### 새 튜닝 스크립트 추가 시
1. `packer/scripts/` 에 스크립트 생성 (예: `XX-my-tuning.sh`)
2. 모든 `*.pkr.hcl` 파일의 provisioner 섹션에 추가
3. `07-check-tuning.sh`에 검증 로직 추가

### 새 Packer 변수 추가 시
1. `packer/variables.pkr.hcl` (없으면 생성)에 변수 정의
2. 각 `*.pkr.hcl` 템플릿에서 `var.변수명`으로 참조

### 새 Provider/Architecture 추가 시
1. `packer/` 에 새 템플릿 생성 (예: `qemu-arm64.pkr.hcl`)
2. `packer/build.sh`에 빌드 케이스 추가
3. `upload-boxes.sh`에 업로드 로직 추가
4. `.github/workflows/`에 CI 추가

## OS Tuning Categories

| Category | File | Key Settings |
|----------|------|--------------|
| 커널 파라미터 | `02-os-tuning.sh` | `net.core.*`, `vm.*`, `fs.*` |
| K8s 전제조건 | `04-k8s-prereq.sh` | swap off, modules, ip_forward |
| 디스크 I/O | `05-disk-tuning.sh` | scheduler, read_ahead |
| 네트워크 | `06-nic-tuning.sh` | ring buffer, offload |
| Ubuntu 24.04 | `ubuntu2404-tuning.sh` | THP, journald |

## CI/CD Workflow

```
Push/PR
   │
   ├──> build-amd64.yml ──> VirtualBox AMD64 + VMware AMD64
   │
   └──> build-arm64.yml ──> VirtualBox ARM64 + VMware ARM64
                                     │
                                     v
                              Vagrant Cloud Upload
                              (on release tag)
```

## Version Info

- Box Name: `dasomel/ubuntu-24.04`
- Current Version: `0.1.1`
- Base OS: Ubuntu 24.04 LTS Cloud Image
