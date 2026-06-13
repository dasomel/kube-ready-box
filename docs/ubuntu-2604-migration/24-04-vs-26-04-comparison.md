# Ubuntu 24.04 vs 26.04 — 차이 · 성능 · 보안 (K8s Box 관점)

> Resolute Raccoon(26.04, 2026-04-23)은 LTS 한 칸 점프치고는 근 10년 만에 가장 큰 변화:
> 커널 메이저 버전업, Rust 기반 유저랜드, cgroup v1 완전 제거, PQC 기본화.

## TL;DR

| 영역 | 24.04 (Noble) | 26.04 (Resolute) | K8s Box 영향 |
|------|---------------|------------------|--------------|
| 커널 | 6.8 | **7.0** | 튜닝 sysctl/THP 재검증 필요(빌드서 통과 확인) |
| init/시스템 | systemd 255 | **systemd 259.5** | cgroup v1 제거 → v2 전용 |
| cgroup | v2 기본(v1 잔존) | **v1 완전 제거** | kubelet/containerd `systemd` 드라이버 필수 |
| 컨테이너 런타임 | containerd 1.7.x | **containerd 2.2.2 / runc 1.4.0** | 최신 런타임 기본 제공 |
| 암호화 | TLS 1.2+, 전통 알고리즘 | **PQC 기본**(커널·OpenSSL 3.5·OpenSSH 10.2) | SSH/TLS 보안 강화(구형 클라 주의) |
| 핵심 유틸 | GNU coreutils, sudo | **Rust 재작성**(uutils, sudo-rs) | 프로비저닝 `sudo` 호환 확인됨 |
| Python | 3.12 | **3.13** | 도구/스크립트 호환 점검 |
| FDE | LUKS | **TPM-backed FDE** | 서버 박스엔 비적용 |
| 데스크톱 | GNOME 46 / Xorg | GNOME 50 / **Wayland 전용** | 서버 이미지 무관 |

---

## 1. 커널 6.8 → 7.0
- **확장형 스케줄러 프레임워크(sched_ext)** 정식 — eBPF로 스케줄링 정책 교체 가능. K8s 노드에서 워크로드 맞춤 스케줄링 여지(본 박스는 기본값 사용).
- 크래시 덤프 기본 활성화, 신규 HW enablement(Intel Nova Lake, AMD Zen 6 등).
- Rust 커널 지원 "experimental" 딱지 제거, RT 커널이 Ubuntu Pro 없이 main 아카이브 제공, Livepatch ARM64 지원, ZFS 2.4.1.
- **영향**: `ubuntu-tuning.sh`의 sysctl/THP(`madvise`)/systemd-oomd 설정이 7.0에서 정상 적용됨(검증 빌드 로그 Complete 확인). 안정 ABI라 회귀 없음.

## 2. 보안 향상 (대부분 "무료"로 따라옴)
- **Post-Quantum Cryptography 기본화**: 커널, OpenSSL **3.5**, OpenSSH **10.2** 전반. 양자내성 알고리즘이 기본 협상.
- **레거시 암호 제거**: RFC 8996 준수(TLS 1.0/1.1 폐기), 구형 알고리즘 정리.
- **cgroup 마운트 강화**: `nsdelegate`, `memory_recursiveprot`, `memory_hugetlb_accounting` — 컨테이너 격리 경계가 현대적 기반 위에 구축.
- **Rust 유저랜드(메모리 안전)**: `sudo-rs`, uutils coreutils로 일부 핵심 도구 대체 → 메모리 안전성 ↑.
- **AppArmor** 지속 강화(스냅 앱 권한 프롬프트 등).
- **영향**: 박스의 기본 보안 자세가 상향. 단, **PQC/레거시 제거로 아주 구형 SSH/TLS 클라이언트 호환성** 주의(Vagrant insecure key SSH는 빌드서 정상 동작 확인).

## 3. 컨테이너 / Kubernetes 관련 (가장 중요)
- 🔴 **cgroup v1 완전 제거(systemd 259)**: 26.04에서 cgroup v1 워크로드는 동작 불가. v1을 강제하던 구형 컨테이너/설정은 깨짐.
  - 본 박스는 24.04도 이미 cgroup v2 unified 기본 → `04-k8s-prereq.sh` 추가 작업 없음. **단 K8s 설치 시 kubelet + containerd `SystemdCgroup=true` 필수**(post-install 문서에 명시 권장).
  - 확인: `stat -fc %T /sys/fs/cgroup` → `cgroup2fs`.
- **containerd 2.2.2 / runc 1.4.0** 최신 런타임 기본. CRI v1, cgroup v2 완전 대응.
- 강화된 cgroup 회계(`memory_hugetlb_accounting`)로 K8s 메모리 제한 정확도 향상.

## 4. 성능 관점
- **sched_ext**: 워크로드 특화 스케줄러 교체 가능(지연/처리량 튜닝 여지).
- 커널 7.0 메모리 관리/네트워킹 개선. (단 7.0 회귀로 일부 DB는 huge pages 권장 — 본 박스 무관.)
- 최신 런타임/툴체인(Python 3.13, glibc/GCC 갱신)으로 빌드·실행 효율 개선.

## 5. 이 프로젝트에 좋아지는 것 / 주의점
**좋아지는 것**
- 보안 기본값 상향(PQC·OpenSSH 10.2·하드닝 cgroup) — 추가 작업 없이 박스 보안 강화.
- 최신 containerd 2.2.2/runc 1.4.0 — K8s 노드 런타임 현대화.
- 커널 7.0 — 신형 HW·스케줄러·라이브패치(ARM64).

**주의점**
- cgroup v1 의존 워크로드 비호환(본 박스는 v2라 영향 적음, 사용자 클러스터 설정 확인 필요).
- 구형 SSH/TLS 클라이언트 PQC/레거시 제거 영향.
- `sudo-rs`/uutils 엣지케이스 — 비표준 sudo 플래그/스크립트 동작 차이 가능(현 프로비저닝은 정상 검증).
- Python 3.13 — 도구 체인 호환 점검.

## 6. 권장 후속 문서 반영
- `docs/k8s-post-install.md`: cgroup v2 + `SystemdCgroup=true` 명시, `stat -fc %T /sys/fs/cgroup` 확인 절차.
- `docs/usage.md`: 26.04 박스의 PQC/OpenSSH 10.2 관련 구형 클라 주의.

## 출처
- https://canonical.com/blog/canonical-releases-ubuntu-26-04-lts-resolute-raccoon
- https://documentation.ubuntu.com/release-notes/26.04/ (및 changes-since-previous-interim, summary-for-lts-users)
- https://canonical.com/blog/ubuntu-26-04-lts-security-updates
- https://www.msbiro.net/posts/ubuntu-2604-lts-security-container-workloads/
- https://computingforgeeks.com/ubuntu-2604-lts-features/
- https://ubuntuhandbook.org/index.php/2026/04/ubuntu-26-04-lts-released-with-kernel-7-0-gnome-50-more/
- https://www.omgubuntu.co.uk/2026/04/ubuntu-26-04-lts-changes-since-24-04
- https://kubernetes.io/docs/setup/production-environment/container-runtimes/

> 버전 수치(containerd/runc/systemd 등)는 출시 시점 자료 기준 — 릴리스 전 `apt policy <pkg>`로 실측 권장.
