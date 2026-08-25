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

5. **VMware Fusion 라이선스 (해소됨)**
   - 과거: 무료 버전에서 headless 빌드 실패 → Fusion Pro 필요
   - 현재: Fusion이 전 사용자 무료로 전환되어 라이선스 제약 없음 (확인 버전 26.0.0)

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

### NixOS 박스 관련 (`nixos/`)

15. **ARM64에서는 nixos-generators가 Vagrant 박스를 못 만든다**
    - `vagrant-virtualbox` 포맷: nixpkgs가 게스트 확장용 `pkgsi686Linux`를 요구 → `i686 Linux package set can only be used with the x86 family`로 평가 단계 중단
    - `vagrant-libvirt` 포맷: 애초에 존재하지 않음 (`nixos-generate --list`로 확인)
    - 해결: `raw-efi`/`vmware`로 디스크 이미지만 만들고 `nixos/package-box.sh`로 직접 패키징

16. **디스크 이미지 빌드는 `kvm` 시스템 기능을 요구하는데 Docker Desktop VM에는 `/dev/kvm`이 없다**
    - 증상: `Required features: {kvm}` / `Available features: {benchmark, big-parallel, nixos-test, uid-range}`
    - 우회: 컨테이너의 `/etc/nix/nix.conf`에 `system-features = kvm ...` 선언. 가속 없이 돌아가며 `error while reading directory ...: Invalid argument` 경고가 대량 발생하지만 산출물은 정상(부팅 검증 완료)
    - 근본 해결: Docker Desktop 중첩 가상화(Apple M3+ / macOS 15+) 또는 `system.image.repart` 전환

17. **vagrant-qemu는 libvirt 박스 형식을 그대로 쓴다**
    - 플러그인이 `provider(:qemu, box_format: "libvirt", ...)`로 선언 → macOS 전용 박스를 따로 만들 필요가 없고, `metadata.json`에 `provider: qemu`라고 쓰면 `vagrant up --provider qemu`가 박스를 영영 못 찾는다
    - 레지스트리의 공개 qemu 박스들도 전부 `libvirt` 프로바이더로 등록돼 있음

18. **NixOS 게스트 + Vagrant 조합의 3대 함정** (모두 `vagrant up` 실패)
    - 로그인 셸: Vagrant 기본 `bash -l` 래핑에서 게스트 stdout이 전달되지 않아 키 교체 단계가 `odd number of arguments for Hash`로 죽음 → 박스 Vagrantfile에 `config.ssh.shell = "bash"`
    - `/etc/fstab`: 스토어를 가리키는 읽기 전용 심볼릭 링크 → Vagrant 정리 단계가 `Read-only file system`으로 실패 → 활성화 스크립트로 최초 1회 실제 파일 변환
    - 공유 폴더: 게스트에 vboxsf/open-vm-tools가 없어 SMB로 폴백, 호스트 자격증명을 대화형으로 물어 자동화가 정지 → 박스 Vagrantfile에서 기본 공유 폴더 비활성화

19. **VMware VMX를 최소 구성으로 직접 쓰면 `vmrun`이 SIGSEGV로 죽는다**
    - 증상: `Unexpected signal: 11` (박스 등록·클론·네트워크 준비까지는 정상)
    - 원인: `svga.*`, `pciBridge0/4~7`, `monitor.phys_bits_used` 등 구조 항목 누락
    - 해결: 검증된 ARM64 박스의 VMX 구성을 그대로 따를 것. 디스크는 SATA(`sata0:0`)에 물리고 `nvme0.present = "FALSE"`

### CI / 검증 하네스 관련

20. **`set -euo pipefail` 아래서 `[ ... ] && var=...` 로 끝나는 헬퍼는 항상 1을 반환한다**
    - 조건이 거짓이면 함수의 종료 상태가 1이 되고, bare 호출(`add foo PASS 1`)은 그 자리에서 스크립트를 죽인다. 출력도 에러 메시지도 없이 exit 1만 남는다
    - `&&` 리스트 *안*에서의 실패는 set -e 면제 대상이지만, 그 함수를 **bare 로 호출한 지점**은 면제가 아니다. 이 차이 때문에 눈으로는 안 보인다
    - 실제 피해: 6개 readiness 스크립트(`network/` `storage/` `time/` `security/` `rocky/` `nixos/`)가 전부 첫 검사에서 죽어 출력 0바이트였다. 각각 이슈 #17 #18 #19 #16 #15 #9의 산출물이고 전부 완료로 보고돼 있었다
    - 해결: 마지막 문장을 `case "$st" in FAIL) ...;; UNKNOWN) ...;; esac` 로. `case` 는 매칭 실패해도 0을 반환한다
    - 같은 함정: `grep ... | cut ...` 을 그대로 반환하는 함수 → 키가 없으면 1을 반환해 호출부의 bare 대입(`v=$(get_field x)`)이 죽는다. `|| true` 로 흡수할 것

21. **집계기가 실패를 삼키면 CI 초록은 거짓말이다**
    - `tools/kube-ready-contracts.sh` 는 파싱 불가한 리포트를 `evidence: null` 로 기록하고 exit 0 으로 끝냈다. CI는 5개 중 4개가 null 인 채로 통과했다
    - 판정 기준을 분리할 것: `status: FAIL` 은 정당한 **검사 결과**(환경 문제)이므로 통과, **증거 부재**는 도구 결함이므로 실패. 지금은 `evidence_missing[]` 이 비면 통과, 아니면 exit 1 (`ALLOW_MISSING_EVIDENCE=1` 로만 예외)
    - 검증 도구를 고쳤으면 **양방향**으로 확인할 것 — 정상 트리에서 통과하는 것만으로는 부족하고, 일부러 깨뜨렸을 때 빨간불이 뜨는지도 봐야 한다

22. **`main` CI가 빨간 채로 방치되면 가드는 없는 것과 같다**
    - 2026-08 기준 15회 연속 실패 상태에서 커밋 9개가 그 위에 얹혔다. 차단 원인은 사소했다: shellcheck 경고 1건, 그리고 Rust 계약 테스트가 `target/debug/` 를 보는데 CI는 `--release` 만 빌드한 것(→ 첫 줄에서 즉사, 한 번도 실행된 적 없음)
    - 푸시 후 `gh run list --limit 1` 로 결과를 확인할 것. 빨간불을 발견하면 새 작업보다 그것을 먼저 고친다
    - 로컬에서 CI와 동일한 명령을 그대로 재현할 수 있다:
    ```bash
    find packer/scripts nixos rocky security network storage time observability tools rust \
      -type f -name '*.sh' -print0 | xargs -0 -r shellcheck --severity=warning
    bash -n tools/*.sh network/*.sh storage/*.sh time/*.sh security/*.sh observability/*.sh rocky/*.sh nixos/*.sh
    ```

23. **리눅스 타깃 스크립트는 컨테이너에서 실제로 돌려볼 것**
    - macOS 에서는 `/proc` `/sys` 가 없어 검증이 불가능하고, 문법 검사만으로는 위 20번 같은 결함이 안 잡힌다
    - `docker run --rm --entrypoint bash -v "$PWD:/w" -w /w <python3 있는 이미지> -c 'bash 스크립트'`
    - 주의: macOS 의 `/tmp` 는 Docker Desktop 공유 경로가 아니다. `-v /tmp/x:/w` 는 조용히 빈 마운트가 되어 "No such file or directory" 로 오판하게 된다. 비교용 사본은 **리포 하위**에 만들 것


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
- [build-inputs.md](docs/build-inputs.md) - 외부 빌드 입력 전수조사/고정 현황 (#30)
- [public-rfp-readiness.md](docs/public-rfp-readiness.md) - 공공 RFP 검증 프로파일 요구사항 대조 (#5)
- [portfolio-contract.md](docs/portfolio-contract.md) - Dasomel OSS Portfolio 공통 Make/CI/SBOM/license 계약 대조 (#28)
