# Phase 4 — 문서/메타

날짜: 2026-06-13 / 상태: ✅ 완료 (검증 통과)

## 설계
- 빌드 중 VM 내부에서 실행되는 메타 스크립트는 **하드코딩 대신 런타임 `/etc/os-release` 감지** → 어떤 Ubuntu 버전이든 자동 대응.
- 문서는 24.04/26.04 병행 + `--version` 사용법 반영. 24.04는 유지(additive).

## 변경 파일
| 파일 | 변경 |
|------|------|
| `packer/scripts/generate-sbom.sh` | `UBUNTU_VER=$(. /etc/os-release && echo $VERSION_ID)`(L10), SBOM `name`/`base_os` → `${UBUNTU_VER}` |
| `packer/scripts/license-info.sh` | `UBUNTU_VER`(L9), info.txt heredoc 변수 전개(6곳), MOTD는 로그인 시 `_VER` 재감지 |
| `packer/scripts/upload-all.sh` | LEGACY 주석(루트 upload-boxes.sh가 정본 명시) + `UBUNTU_VERSION`→`BOX_NAME` 최소 파라미터화 |
| `README.md` / `README.ko.md` | 배지·소개·Vagrant Cloud·빠른시작·빌드명령·CI·라이선스 전반 병행 반영 |
| `CLAUDE.md` | L7 "24.04 / 26.04", L14 `ubuntu-tuning.sh` |
| `CHANGELOG.md` | `[Unreleased]` 섹션 추가 (26.04 coexist) |
| `.claude/hooks/load-project-context.sh` | L14 "Ubuntu 24.04 / 26.04" |

## 검증
| 체크 | 결과 |
|------|------|
| `bash -n` (4개 스크립트) | PASS |
| `shellcheck` | SC1091(info)만 — `/etc/os-release` 호스트 부재, 오탐 |
| heredoc 오전개 위험 (license-info.sh) | 없음 — info.txt body는 `${UBUNTU_VER}`만, MOTD는 `'SCRIPT'` 따옴표 보호 |
| 잔여 `24.04` | 전부 의도적 (병행 표기/Vagrant Cloud 24.04 URL/CHANGELOG 이력) |

## upload-all.sh 결정
로직 재작성 안 함. 루트 `upload-boxes.sh`가 완전 파라미터화된 정본이므로, 레거시 표시 주석 + 최소 변수화만 적용.
