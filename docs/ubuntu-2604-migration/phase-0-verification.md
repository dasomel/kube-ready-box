# Phase 0 — 사전 검증

날짜: 2026-06-13 / 판정: **마이그레이션 난이도 낮음**

## 1. ISO 실측값 (검증 완료)

| 항목 | 값 |
|------|-----|
| amd64 URL | `https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso` |
| amd64 SHA256 | `sha256:dec49008a71f6098d0bcfc822021f4d042d5f2db279e4d75bdd981304f1ca5d9` |
| arm64 URL | `https://cdimage.ubuntu.com/releases/26.04/release/ubuntu-26.04-live-server-arm64.iso` |
| arm64 SHA256 | `sha256:c9aa567e6560b2eddae3af03fc686002e35b6fee96f97fd5df3271e846439fdd` |

> ⚠️ 파일명에 포인트 릴리스 없음 (`26.04`, 24.04는 `24.04.3`). ISO 파일명을 `ubuntu_version`만으로
> 조합하면 깨짐 → 전체 URL을 버전별 맵으로 보관(Phase 1 설계).
> amd64는 kernel.org 미러(`https://mirrors.edge.kernel.org/ubuntu-releases/26.04/...`)도 동일 체크섬으로 사용 가능.

## 2. autoinstall 스키마 — 호환 (저위험)
- `version: 1` 여전히 유일·유효 (min=max=1)
- `storage / network / packages / late-commands / identity / ssh` 구조 변경 없음 → 기존 `user-data`(ext4·xfs) 그대로 동작 예상
- 네트워크 인터페이스 명명(`en*` 매처) 변경 문서화 없음 → 유지 가능
- 유일 deprecation `ubuntu-advantage`→`ubuntu-pro` : 본 프로젝트 미사용, 영향 없음

## 3. 신규 발견 리스크 (실빌드에서 재검증)
| 리스크 | 영향 | 대응 |
|--------|------|------|
| 🔴 커널 Linux 7.0 (24.04은 6.x) | `ubuntu2404-tuning.sh` sysctl/THP/systemd-oomd | 실빌드 1회 검증 (Phase 5) |
| 🟡 cgroup v1 완전 제거 (v2 전용) | K8s 런타임 | 24.04도 이미 v2 unified 기본 → `cgroupDriver=systemd` 전제 확인만 |
| 🟢 `/media`→`/run/media`, PostgreSQL huge pages | 무관 | 조치 없음 |

## 종합
가장 우려했던 autoinstall·네트워크 매처가 그대로 유지되어 위험 해소.
남은 실질 검증은 **커널 7.0 위 튜닝 스크립트 실빌드 1회**뿐. 나머지는 기계적 버전 변수화.

## 출처
- https://canonical.com/blog/canonical-releases-ubuntu-26-04-lts-resolute-raccoon
- https://documentation.ubuntu.com/release-notes/26.04/changes-since-previous-interim/
- https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-schema.html
- https://releases.ubuntu.com/26.04/SHA256SUMS
- https://cdimage.ubuntu.com/releases/26.04/release/SHA256SUMS
