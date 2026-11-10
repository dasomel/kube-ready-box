# 보안 대응 이력

[English](security-response.md) | 한국어

최신순으로 정리한 발견·대응 기록입니다. Trivy는 박스 디스크에서 추출한 패키지 DB에서 배포판 수정 버전이 존재하는 항목을 집계합니다. 수정 가능 항목이 0이어도 모든 취약점이 없다는 뜻은 아니며, 업스트림 미수정 취약점은 이 측정 범위에 포함되지 않으며, 독립 실행 파일은 일일 스캔이 추출하기 전까지 범위 밖이었습니다. 2026-11-08 기록은 패키지/CVE 쌍을 집계하며 배포한 각 provider 이미지의 검증 근거를 연결합니다. 이전 기록은 당시 측정 범위와 [11월 재빌드 기록](../research/evidence/2026-11.jsonl)을 유지합니다.

## 2026-11-08 — 일일 Box CVE 스캔(#100) 및 v0.3.2 재빌드

| 발견 사항·영향받는 박스 | 상태·수정 버전 | 근거 |
| --- | --- | --- |
| Ubuntu 24.04 게시 0.3.1(`ext4`·`xfs`, `vmware_desktop` arm64 및 `virtualbox` amd64): 수정 가능한 CVE HIGH 4(패키지/CVE 쌍, `apt` 계열의 `CVE-2026-109518`) / MEDIUM 21. | **v0.3.2 / 박스 0.3.2에서 수정(2026-11-08):** 수정 가능 CVE 0건(릴리스 전 후보 박스를 로컬 Trivy로 검사). `apt` 2.8.4ubuntu0.1, 커널 6.8.0-149-generic. | [이슈 #100](https://github.com/dasomel/kube-ready-box/issues/100), [PR #98](https://github.com/dasomel/kube-ready-box/pull/98), [재빌드 기록](releases/v0.3.2-evidence.json) |
| Ubuntu 26.04 게시 0.3.1(`ext4`·`xfs`, `vmware_desktop` arm64 및 `virtualbox` amd64): 수정 가능한 CVE HIGH 3(패키지/CVE 쌍, `apt` 계열의 `CVE-2026-109518`) / MEDIUM 22. | **v0.3.2 / 박스 0.3.2에서 수정(2026-11-08):** 수정 가능 CVE 0건(릴리스 전 후보 박스를 로컬 Trivy로 검사). `apt` 3.2.1ubuntu0.1, 커널 7.0.0-43-generic. | [이슈 #100](https://github.com/dasomel/kube-ready-box/issues/100), [PR #98](https://github.com/dasomel/kube-ready-box/pull/98), [재빌드 기록](releases/v0.3.2-evidence.json) |
| Rocky 9 게시 0.1.1(`ext4`·`xfs`, `vmware_desktop` arm64): 커널 errata(5.14.0-687.64.1 / 687.66.1에서 수정)로 인한 수정 가능한 CVE HIGH 198건(패키지/CVE 쌍)(이전에 Rocky에서 open-upstream으로 분류됐던 CVE-2026-98432 포함). | **v0.3.2 / 박스 0.1.2에서 수정(2026-11-08):** 수정 가능 CVE 0건(릴리스 전 후보 박스를 로컬 Trivy로 검사). 커널 5.14.0-687.66.1.el9_8.aarch64. | [이슈 #100](https://github.com/dasomel/kube-ready-box/issues/100), [PR #98](https://github.com/dasomel/kube-ready-box/pull/98), [재빌드 기록](releases/v0.3.2-evidence.json) |
| Ubuntu 24.04/26.04: CVE-2026-98432. | **버전 대조 확인 / 배포판 추적은 pending:** 후보의 커널 패키지 `6.8.0-149.149`·`7.0.0-43.43`는 Canonical이 수정 포함 빌드로 안내한 버전과 일치한다. 2026-11-08 확인한 CVE JSON은 두 LTS를 여전히 `pending`으로 표시한다. 수정 가능 CVE 스캔만으로 이 추적 상태를 PASS로 바꾸지 않는다. | [Canonical 수정 빌드 안내](https://ubuntu.com/blog/fixes-available-in-proposed-pocket-for-cve-2026-98432), [공식 CVE JSON](https://ubuntu.com/security/cves/CVE-2026-98432.json), [재빌드 기록](releases/v0.3.2-evidence.json) |

일일 Box CVE 스캔([PR #98](https://github.com/dasomel/kube-ready-box/pull/98))이 2026-11-08 [이슈 #100](https://github.com/dasomel/kube-ready-box/issues/100)을 자동으로 열어 시작된 재빌드입니다. `v0.3.2`는 기록된 소스 리비전과 기존 실행 파일 핀으로 재빌드했고, PR #101의 다운로드 오류 처리 보완을 포함하며, 종료된 Vagrant Cloud 페이지 대신 GitHub Pages 카탈로그를 가리키도록 `/etc/vagrant-box/info.txt`를 고친 `license-info.sh` 카탈로그 URL 수정([PR #94](https://github.com/dasomel/kube-ready-box/pull/94), [c630456](https://github.com/dasomel/kube-ready-box/commit/c630456))도 함께 반영됩니다. 빌드·부팅 검증 경로는 0.3.1과 동일합니다(`vmware_desktop` arm64는 로컬 VMware Fusion에서 빌드·부팅 검증, `virtualbox` amd64는 `.github/workflows/build-amd64.yml`에서 빌드·부팅 테스트). NixOS 0.2.2는 변경 없이 `v0.3.0`에 유지됩니다.

## 2026-11-01 — 박스 패키지·커널 조치

| 발견 사항·영향받는 박스 | 상태·수정 버전 | 근거 |
| --- | --- | --- |
| Rocky 9 게시 0.1.0 계열: 수정 가능한 CVE CRITICAL 5 / HIGH 411 / MEDIUM 22(총 438). 빌드 후 재부팅하지 않아 설치 커널 5.14.0-687.10.1이 남았고, 여기에 CVE 399건이 포함됨. | **v0.3.0에서 수정(2026-11-01):** 수정 가능 CVE 0건. 부팅 검증에서 커널 5.14.0-687.61.1.el9_8만 확인. | [커널 제거 c2e6de3](https://github.com/dasomel/kube-ready-box/commit/c2e6de3), [PR #84](https://github.com/dasomel/kube-ready-box/pull/84), [Rocky xfs 빌드 수정 PR #86](https://github.com/dasomel/kube-ready-box/pull/86) |
| Ubuntu 26.04 로컬 사전 빌드: 수정 가능 CVE CRITICAL 2 / HIGH 104 / MEDIUM 866 / LOW 169. | **v0.3.0에서 수정(2026-11-01):** 수정 가능 CVE 0건. 커널 7.0.0-42, curl 8.18.0-1ubuntu2.8, OpenSSL 3.5.5-1ubuntu3.7. | [PR #84](https://github.com/dasomel/kube-ready-box/pull/84), [재빌드 기록](../research/evidence/2026-11.jsonl) |
| Ubuntu 24.04 재빌드 박스. | **v0.3.0에서 수정(2026-11-01):** 수정 가능 CVE 0건. 커널 6.8.0-147. | [재빌드 기록](../research/evidence/2026-11.jsonl), [PR #84](https://github.com/dasomel/kube-ready-box/pull/84) |
| NixOS 게시 0.2.0(커널 6.18.36): CVE-2026-98432(Linux IPv4 TCP use-after-free). | **0.2.1·0.2.2에서 수정됨:** 업스트림 수정 e3f33b0a1d89는 Linux 6.18.56부터 포함. 0.2.2는 커널 6.18.60 및 CVE-2026-106552·CVE-2026-106583을 수정한 OpenSSH 10.6p1 사용. 게시된 0.2.0은 영향받음. | [NixOS 갱신 169bb21](https://github.com/dasomel/kube-ready-box/commit/169bb21), [kernel.org ChangeLog-6.18.56](https://cdn.kernel.org/pub/linux/kernel/v6.x/ChangeLog-6.18.56) |
| Ubuntu 24.04/26.04 및 Rocky 9: CVE-2026-98432. | **업스트림 수정 대기(open-upstream):** 작성 당시 USN/RHSA 없음. 배포판 수정판이 나오면 재빌드. | [업스트림 수정 e3f33b0a1d89](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=e3f33b0a1d89) |
| gVisor 20260817.0: CVE-2026-95702 및 Go 표준 라이브러리 CVE-2026-78660, CVE-2026-97031, CVE-2026-111943. | **수정됨(재빌드):** gVisor 20261026.0. 리뷰 중 `runsc`에 `gvisor-bin/gvisor_sentry`가 필요한 sidecar 회귀를 발견해 조치. | [갱신 4d579ce](https://github.com/dasomel/kube-ready-box/commit/4d579ce), [빌드 입력](build-inputs.md) |
| `yq` v4.44.3(Go 1.22.5). | **완화·예외 수용(accepted-exception):** v4.54.1(Go 1.27.1)로 갱신. 남은 Go CVE는 Go >= 1.27.3 필요. `yq`에서 도달 가능한지는 확인되지 않음. | [갱신 4d579ce](https://github.com/dasomel/kube-ready-box/commit/4d579ce), [빌드 입력 예외](build-inputs.md) |
| `dool` 1.3.8: CVE-2026-56651, CVE-2026-56652. | **예외 수용(accepted-exception):** 수정된 업스트림 릴리스 없음. 릴리스가 나오면 갱신. | [빌드 입력 예외](build-inputs.md) |
| `yq` v4.54.1(go1.27.1, x/net v0.59.0): HIGH CVE-2026-78661, CVE-2026-78667, CVE-2026-78669(수용된 CVE-2026-78660/97031/111943 외), 바이너리 스캔으로 발견([PR #109](https://github.com/dasomel/kube-ready-box/pull/109)). | **v0.3.3 / Ubuntu 박스 0.3.3, Rocky 박스 0.1.3에서 수정(2026-11-10):** `yq` v4.54.3(go1.27.3, x/net v0.62.0). 소스 수정은 [PR #111](https://github.com/dasomel/kube-ready-box/pull/111). 배포된 v0.3.2 박스 전체가 v4.54.1을 포함했습니다. 후보 박스는 모두 Trivy 0.76.0(OS 패키지 및 독립 실행 파일, `yq` 포함)으로 검사했고 수정 가능 CVE는 0건입니다. | [빌드 입력](build-inputs.md), [PR #109](https://github.com/dasomel/kube-ready-box/pull/109), [릴리스 v0.3.3](https://github.com/dasomel/kube-ready-box/releases/tag/v0.3.3), [이슈 #112](https://github.com/dasomel/kube-ready-box/issues/112), [재빌드 기록](releases/v0.3.3-evidence.json) |

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

Vagrant Cloud(HCP Vagrant) 서비스가 종료됩니다. 기존 게시 버전은 2026-12-31까지 남지만 수정판이 제공되지 않습니다. 패치된 박스는 GitHub Release v0.3.0(2026-11-01 출시)과 Pages 카탈로그로 배포합니다. 게시된 0.2.0, 1.1.0, 0.1.0 사용자는 해당 박스로 이동하거나 `apt`/`dnf` 업그레이드 후 재부팅해야 합니다. 이 저장소 기록만으로 원격 릴리스의 모든 산출물을 독립 검증하지는 않았습니다.

## 대응 방식

박스 디스크에서 추출한 패키지 DB를 Trivy로 검사하고, 패키지 전체 업그레이드 후 재빌드·교차 리뷰·부팅 검증을 거쳐 패치된 박스를 게시합니다. 업스트림 수정판이 없는 항목은 배포판 수정판으로 재빌드할 수 있을 때까지 열린 상태로 둡니다. 수정판이 나오는 시점을 놓치지 않도록 [Box CVE scan](../.github/workflows/box-cve-scan.yml) 워크플로가 매일 실행됩니다(`tools/box-cve-scan.sh`). 배포 중인 박스를 Pages 카탈로그 그대로 내려받아 체크섬을 확인하고, dpkg/rpm DB와 패키지 관리자 밖에서 설치한 독립 실행 파일(allowlist: `yq`, gVisor `runsc`/shim/`gvisor-bin`)을 읽기 전용으로 꺼내 Go stdlib/모듈 CVE를 포함해 Trivy로 수정 가능한 CVE를 셉니다. 검사한 바이너리는 `summary.json`에 기록됩니다. [build-inputs.md](build-inputs.md)에 수용된 예외로 문서화된 항목은 `tools/box-cve-scan.trivyignore.yaml`(바이너리 단위 범위, 만료일이 지나면 다시 실패)로 억제하며 요약의 `accepted`에는 남습니다. CRITICAL 또는 HIGH가 있으면 실패하며, 이것이 재빌드 신호입니다. NixOS는 dpkg/rpm DB가 없어 PASS가 아닌 UNKNOWN으로 보고합니다. 로컬 재빌드 기록은 [2026-11.jsonl](../research/evidence/2026-11.jsonl)에 기록합니다.

## 취약점 보고

취약점은 [SECURITY-ko.md](../SECURITY-ko.md)의 절차에 따라 비공개로 보고해 주십시오.
