# 보안 대응 이력

[English](security-response.md) | 한국어

최신순으로 정리한 발견·대응 기록입니다. 아래 Trivy 수치는 박스 디스크에서 추출한 패키지 DB를 검사해 집계한 **수정 버전이 존재하는 고유 CVE ID**입니다. 이 수치가 0이어도 업스트림 수정판이 없는 취약점은 남습니다. 로컬 재빌드 측정값이며, 게시된 모든 provider 이미지를 검사했다는 뜻은 아닙니다. 수치는 박스 디스크에서 추출한 패키지 DB의 Trivy rootfs 검사 결과(2026-11-01 세션 측정, 원본 출력은 커밋되지 않음)입니다. 아래 커널·패키지 버전은 2026-11-01 재빌드 박스의 부팅 검증에서 확인했습니다. 빌드 기록은 [2026-11.jsonl](../research/evidence/2026-11.jsonl)에 있습니다([1차 기록](https://github.com/dasomel/kube-ready-box/commit/325f107), [2차 기록](https://github.com/dasomel/kube-ready-box/commit/5528164)).

## 2026-11-01 — 박스 패키지·커널 조치

| 발견 사항·영향받는 박스 | 상태·수정 버전 | 근거 |
| --- | --- | --- |
| Rocky 9 게시 0.1.0 계열: 수정 가능한 CVE CRITICAL 5 / HIGH 411 / MEDIUM 22(총 438). 빌드 후 재부팅하지 않아 설치 커널 5.14.0-687.10.1이 남았고, 여기에 CVE 399건이 포함됨. | **로컬 재빌드에서 수정(아직 미게시):** 수정 가능 CVE 0건. 부팅 검증에서 커널 5.14.0-687.61.1.el9_8만 확인. | [커널 제거 c2e6de3](https://github.com/dasomel/kube-ready-box/commit/c2e6de3), [PR #84](https://github.com/dasomel/kube-ready-box/pull/84), [Rocky xfs 빌드 수정 PR #86](https://github.com/dasomel/kube-ready-box/pull/86) |
| Ubuntu 26.04 로컬 1.2.0 빌드: 수정 가능 CVE CRITICAL 2 / HIGH 104 / MEDIUM 866 / LOW 169. | **로컬 재빌드에서 수정(아직 미게시):** 수정 가능 CVE 0건. 커널 7.0.0-42, curl 8.18.0-1ubuntu2.8, OpenSSL 3.5.5-1ubuntu3.7. | [PR #84](https://github.com/dasomel/kube-ready-box/pull/84), [재빌드 기록](../research/evidence/2026-11.jsonl) |
| Ubuntu 24.04 재빌드 박스. | **로컬 재빌드에서 수정(아직 미게시):** 수정 가능 CVE 0건. 커널 6.8.0-147. | [재빌드 기록](../research/evidence/2026-11.jsonl), [PR #84](https://github.com/dasomel/kube-ready-box/pull/84) |
| NixOS 게시 0.2.0(커널 6.18.36): CVE-2026-98432(Linux IPv4 TCP use-after-free). | **0.2.1·0.2.2에서 수정됨:** 업스트림 수정 e3f33b0a1d89는 Linux 6.18.56부터 포함. 0.2.2는 커널 6.18.60 및 CVE-2026-106552·CVE-2026-106583을 수정한 OpenSSH 10.6p1 사용. 게시된 0.2.0은 영향받음. | [NixOS 갱신 169bb21](https://github.com/dasomel/kube-ready-box/commit/169bb21), [kernel.org ChangeLog-6.18.56](https://cdn.kernel.org/pub/linux/kernel/v6.x/ChangeLog-6.18.56) |
| Ubuntu 24.04/26.04 및 Rocky 9: CVE-2026-98432. | **업스트림 수정 대기(open-upstream):** 작성 당시 USN/RHSA 없음. 배포판 수정판이 나오면 재빌드. | [업스트림 수정 e3f33b0a1d89](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=e3f33b0a1d89) |
| gVisor 20260817.0: CVE-2026-95702 및 Go 표준 라이브러리 CVE-2026-78660, CVE-2026-97031, CVE-2026-111943. | **수정됨(재빌드):** gVisor 20261026.0. 리뷰 중 `runsc`에 `gvisor-bin/gvisor_sentry`가 필요한 sidecar 회귀를 발견해 조치. | [갱신 4d579ce](https://github.com/dasomel/kube-ready-box/commit/4d579ce), [빌드 입력](build-inputs.md) |
| `yq` v4.44.3(Go 1.22.5). | **완화·예외 수용(accepted-exception):** v4.54.1(Go 1.27.1)로 갱신. 남은 Go CVE는 Go >= 1.27.3 필요. `yq`에서 도달 가능한지는 확인되지 않음. | [갱신 4d579ce](https://github.com/dasomel/kube-ready-box/commit/4d579ce), [빌드 입력 예외](build-inputs.md) |
| `dool` 1.3.8: CVE-2026-56651, CVE-2026-56652. | **예외 수용(accepted-exception):** 수정된 업스트림 릴리스 없음. 릴리스가 나오면 갱신. | [빌드 입력 예외](build-inputs.md) |

재빌드 후 박스 크기 작업은 [1d3abd3](https://github.com/dasomel/kube-ready-box/commit/1d3abd3)에서 진행했습니다. Rocky 첫 부팅의 `sshd-keygen` 순서 경합은 [549239d](https://github.com/dasomel/kube-ready-box/commit/549239d)에서 수정했습니다. VMware 빌드의 간헐적인 SSH 연결 종료([실수 기록 #26](mistakes-log.md))는 박스 취약점이 아닌 빌드 안정성 문제입니다.

## 2026-11-01 — 빌드 입력 공급망

| 발견 사항 | 상태·조치 | 근거 |
| --- | --- | --- |
| `hashicorp/setup-packer@main`이 변동 가능한 참조였음. | **수정됨:** v3.4.0 커밋으로 고정. | [a1d84e4](https://github.com/dasomel/kube-ready-box/commit/a1d84e4) |
| 고정되지 않은 입력을 검사하는 guard가 디렉터리 두 곳만 검사했고, 백슬래시로 끝나는 주석이 다음 다운로드를 숨길 수 있었음. | **수정됨:** 검사 범위와 파서 보완. | [35a5606](https://github.com/dasomel/kube-ready-box/commit/35a5606), [45c3ec4](https://github.com/dasomel/kube-ready-box/commit/45c3ec4) |
| Packer 플러그인 초기화 시 GitHub 요청에 인증을 사용하지 않았음. | **수정됨:** `packer init` 인증 적용. | [PR #85](https://github.com/dasomel/kube-ready-box/pull/85), [40aa827](https://github.com/dasomel/kube-ready-box/commit/40aa827) |

## 2026-10-31 — 증거·릴리스 게이트

| 발견 사항 | 상태·조치 | 근거 |
| --- | --- | --- |
| 릴리스 승격이 FAIL/UNKNOWN 보고서와 누락·불일치 해시를 허용했고, `SHA256SUMS` 경로가 `../` 또는 심볼릭 링크를 통해 이탈할 수 있었음. | **수정됨:** 증거 상태와 산출물 해시 검증. | [PR #83](https://github.com/dasomel/kube-ready-box/pull/83), [243ddb8](https://github.com/dasomel/kube-ready-box/commit/243ddb8) |
| 라이선스 게이트가 `ROOT=` 사용 시 호스트의 copyright 파일을 해시했고, 이미지 안의 절대 경로 심볼릭 링크가 `ROOT`를 벗어났음. | **수정됨:** 이미지 루트에서 해시 계산. | [a41f9e0](https://github.com/dasomel/kube-ready-box/commit/a41f9e0) |
| verifier가 잘못 입력한 플래그를 무시했고, readiness drift가 거짓 `NO_DRIFT`를 보고할 수 있었으며, airgap 검증이 불완전한 번들을 허용했음. | **수정됨:** 잘못된 플래그, 오래된 drift 증거, 불완전 번들 거부. | [7c69e74](https://github.com/dasomel/kube-ready-box/commit/7c69e74), [5780f9d](https://github.com/dasomel/kube-ready-box/commit/5780f9d), [258535a](https://github.com/dasomel/kube-ready-box/commit/258535a) |

## 배포 및 사용자 조치

Vagrant Cloud(HCP Vagrant) 서비스가 종료됩니다. 기존 게시 버전은 2026-12-31까지 남지만 수정판이 제공되지 않습니다. 패치된 박스는 GitHub Release v1.2.0(작성 시점에 아직 미출시)과 Pages 카탈로그를 통해 배포할 예정입니다. v1.2.0 출시 후 게시된 0.2.0, 1.1.0, 0.1.0 사용자는 해당 박스로 이동하거나 `apt`/`dnf` 업그레이드 후 재부팅해야 합니다. 이 저장소 기록만으로 원격 릴리스의 모든 산출물을 독립 검증하지는 않았습니다.

## 대응 방식

박스 디스크에서 추출한 패키지 DB를 Trivy로 검사하고, 패키지 전체 업그레이드 후 재빌드·교차 리뷰·부팅 검증을 거쳐 패치된 박스를 게시할 예정입니다. 업스트림 수정판이 없는 항목은 배포판 수정판으로 재빌드할 수 있을 때까지 열린 상태로 둡니다. 로컬 재빌드 기록은 [2026-11.jsonl](../research/evidence/2026-11.jsonl)에 기록합니다.

## 취약점 보고

취약점은 [SECURITY-ko.md](../SECURITY-ko.md)의 절차에 따라 비공개로 보고해 주십시오.
