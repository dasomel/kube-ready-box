# Phase 6 — OS 튜닝 26.04 감사 및 적용

날짜: 2026-06-13 / 상태: ✅ 적용 (정적 검증 통과 / 런타임 재빌드 검증 권장)

## 목적
24.04에서 적용되던 OS/커널 튜닝이 26.04(커널 7.0 / systemd 259 / cgroup v2 전용)에서
변경·삭제·추가가 필요한지 감사하고 적용.

## 감사 대상 & 판정
| 스크립트 | 설정 | 26.04 판정 | 조치 |
|----------|------|------------|------|
| `ubuntu-tuning.sh` | `kernel.sched_min_granularity_ns`, `sched_wakeup_granularity_ns` | ❌ **무효** — 커널 6.6 EEVDF 교체 시 sysctl→debugfs 이동. 24.04(6.8)·26.04(7.0) 모두 sysctl.d로 설정 불가(조용히 실패) | 🗑️ **삭제** + 사유 주석 |
| `ubuntu-tuning.sh` | THP `madvise` | ✅ 유효 (`/sys/kernel/mm/...` 경로 안정) | 유지 |
| `ubuntu-tuning.sh` | systemd-oomd 비활성 | ✅ 유효 (systemd 259에도 oomd 존재) | 유지 |
| `ubuntu-tuning.sh` | journald 제한 | ✅ 유효 | 유지 |
| `02-os-tuning.sh` | 네트워크/TCP/메모리/fs/conntrack/보안 sysctl | ✅ 6.x→7.0 안정 ABI | 유지 |
| `02-os-tuning.sh` | `vm.max_map_count` | ➕ **누락** — K8s 노드 권장(mmap 다용 워크로드) | **추가 1048576**(아래 ⚠️ 참고) |
| `04-k8s-prereq.sh` | overlay/br_netfilter, bridge-nf, ip_forward, IPv6 비활성, 패키지 | ✅ 변경 없음. cgroup v2는 24.04도 기본이라 추가 작업 불필요 | 유지 |

## 적용된 변경
1. **삭제**: 무효 CFS 스케줄러 sysctl 2종 (EEVDF 이후 debugfs 이동, 비영속·고급 → 기본값 사용 권장하여 미설정)
2. **추가**: `vm.max_map_count = 262144` (`02-os-tuning.sh`, 24·26 공통 개선)
3. **버전 인식**: `ubuntu-tuning.sh`가 `/etc/os-release`로 `VERSION_ID` 감지 + `case` 분기(향후 26 전용 확장 지점). 현재 26 전용 추가 튜닝은 불필요(감사 결과 공통 튜닝으로 충분).

## 26.04 특이사항 (조치 불필요)
- cgroup 마운트 하드닝(`nsdelegate`, `memory_recursiveprot`, `memory_hugetlb_accounting`)은 26.04 기본 제공 → 우리가 설정할 대상 아님.
- cgroup v1 제거: 우리는 v1을 설정하지 않으므로 영향 없음. (K8s 설치 시 `SystemdCgroup=true` 전제는 post-install 문서 사안)

## 검증
| 체크 | 결과 |
|------|------|
| `bash -n` (양 스크립트) | PASS |
| `shellcheck` | SC1091(/etc/os-release)만 — 오탐 |
| `build.sh validate` / `packer validate -var ubuntu_version=26.04` | PASS |
| 무효 CFS sysctl 활성 라인 | 0건 (주석만) |
| `vm.max_map_count` | `02-os-tuning.sh:64` 추가됨 |
| 버전 감지/분기 | `ubuntu-tuning.sh` 존재 |

## 재빌드 런타임 검증 (2026-06-13, `virtualbox-arm64 --fs=xfs --version=26.04`)
| 검증 | 결과 |
|------|------|
| 버전 감지 | ✅ `Detected Ubuntu 26.04 (kernel 7.0.0-22-generic)` — 커널 7.0 실증 |
| case 분기 | ✅ "Ubuntu 26.04: ... no extra tuning needed" 출력 |
| 무효 CFS sysctl 에러 | ✅ 0건 (제거로 부팅 에러 소멸) |
| 전 프로비저닝 Complete + 박스 | ✅ 2.5G 산출 |

### ⚠️ 재빌드가 잡아낸 회귀 — `vm.max_map_count`
26.04는 `/usr/lib/sysctl.d/55-map-count.conf`로 **기본 `vm.max_map_count=1048576`**(systemd 256+)을 설정.
우리 `99-k8s-tuning.conf`는 파일명 정렬상 `55` 뒤에 적용되어, 처음 넣은 `262144`가 **기본값을 낮추는**
회귀를 유발(로그에서 최종 262144 확인).
→ **수정**: 값을 **`1048576`**로 상향. 24.04(기본 65536)는 상향 효과, 26.04는 기본과 동일(회귀 제거),
K8s 권장 최소(262144) 초과. 정적 재검증(packer validate 24/26, shellcheck) 통과.
> 이 값 변경은 1줄 sysctl 이라 적용 메커니즘이 위 빌드에서 이미 입증됨(추가 재빌드 선택).

## 출처
- EEVDF(6.6) CFS 튜너블 debugfs 이동: https://docs.kernel.org/scheduler/sched-eevdf.rst , https://kernel-internals.org/sched/eevdf/
- K8s 노드 sysctl(vm.max_map_count 262144 등): https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/
- 커널 7.0: https://www.phoronix.com/news/Linux-7.0-Released
