# Phase 2 — 빌드/업로드 도구

날짜: 2026-06-13 / 상태: ✅ 완료 (검증 통과)

## 설계
- **BOX semver**(`VERSION`, 예 0.2.3, Vagrant Cloud 릴리스 버전)와 **UBUNTU 버전**(24.04/26.04)을 별도 변수로 분리.
- `UBUNTU_VERSION` default `24.04` 유지. `--version=26.04` 플래그 또는 `UBUNTU_VERSION` env로 전환.

## 변경 파일
| 파일 | 핵심 변경 |
|------|-----------|
| `packer/build.sh` | `UBUNTU_VERSION` 기본변수(L35), `--version=` 플래그 파싱(`--fs` 스타일, L343/351), 잘못된 값 거부(L353), 모든 `packer validate`(L112)·`packer build`(L282)에 `-var ubuntu_version=` 전달, help/배너 갱신 |
| `upload-boxes.sh` | `UBUNTU_VERSION`(box semver와 분리, L9), `--version=` 파싱(L17), box 파일명/box_name/description/URL을 `${UBUNTU_VERSION}`로 |

## 사용법 (26.04 라인)
```bash
./build.sh virtualbox-arm64 --version=26.04     # 개별 빌드
UBUNTU_VERSION=26.04 ./build.sh all             # 전체 빌드 (env)
./upload-boxes.sh --version=26.04               # 업로드
```
(인자 없으면 기존과 동일하게 24.04 빌드)

## 검증
| 체크 | 결과 |
|------|------|
| `bash -n` build.sh / upload-boxes.sh | PASS |
| `shellcheck` | 신규 경고 0 (기존 7건은 미변경 코드) |
| `packer validate` (24.04 기본) | PASS |
| `packer validate` (26.04 선택) | PASS |
| 기본값 24.04 유지 | 확인 |
| 모든 packer 호출에 `ubuntu_version` 전달 | 확인 (L112, L282) |
| 잔여 `ubuntu-24.04` 하드코딩 | 0건 |
