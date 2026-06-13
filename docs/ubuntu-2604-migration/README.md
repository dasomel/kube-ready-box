# Ubuntu 26.04 (Resolute Raccoon) 마이그레이션

> 기존 Ubuntu 24.04 Box 라인과 **병행**으로 26.04 Box 라인을 추가한다.
> 24.04(`dasomel/ubuntu-24.04-*`)는 유지하고, 한 코드베이스에서 `var.ubuntu_version`으로 두 라인을 모두 빌드.

## 핵심 사실
- **26.04 LTS = "Resolute Raccoon"**, 정식 릴리스 2026-04-23
- apt 코드명: `resolute`
- 커널: **Linux 7.0** (24.04은 6.x)
- autoinstall 스키마 `version: 1` 유지, 섹션 구조 변경 없음 → 기존 cloud-init 재사용 가능

## 운영 전략
**병행 (coexist)** — 24.04 유지 + 26.04 신규 추가. 버전 문자열을 변수화하여 공존.

## Phase 진행 현황
| Phase | 내용 | 상태 | 문서 |
|-------|------|------|------|
| 0 | 사전 검증 (ISO/스키마/리스크) | ✅ 완료 | [phase-0-verification.md](./phase-0-verification.md) |
| 1 | 변수화 + 4개 템플릿 | ✅ 완료 | [phase-1-templates.md](./phase-1-templates.md) |
| 2 | 빌드/업로드 도구 | ✅ 완료 | [phase-2-tooling.md](./phase-2-tooling.md) |
| 3 | CI/CD (2개 워크플로우) | ✅ 완료 | [phase-3-cicd.md](./phase-3-cicd.md) |
| 4 | 문서/메타 | ✅ 완료 | [phase-4-docs.md](./phase-4-docs.md) |
| 5 | 검증 빌드 & 릴리스 | 🟡 빌드검증✅/릴리스대기 | [phase-5-release.md](./phase-5-release.md) |
| 6 | OS 튜닝 26.04 감사·적용 | ✅ 적용·재빌드검증 | [phase-6-tuning-audit.md](./phase-6-tuning-audit.md) |
| 7 | CI ARM64 출시 갭 수정 | ✅ 수정 | [phase-7-ci-arm64-publish.md](./phase-7-ci-arm64-publish.md) |

## 참고 자료
- [24-04-vs-26-04-comparison.md](./24-04-vs-26-04-comparison.md) — 24/26 차이·성능·보안 비교
