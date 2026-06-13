# Phase 3 — CI/CD (GitHub Actions)

날짜: 2026-06-13 / 상태: ✅ 완료 (검증 통과)

## 설계 판단
- 매 push마다 두 버전 빌드 = CI 비용 2배 → **matrix 축 추가 안 함**.
- 대신 **`workflow_dispatch` 입력 `ubuntu_version`** (choice: 24.04/26.04, default 24.04) 추가.
- `UBUNTU_VERSION = inputs.ubuntu_version || '24.04'` → push/PR 자동 트리거는 24.04 유지.
- 워크플로우는 build.sh가 아니라 `packer build`를 직접 호출 → 각 packer validate/build 스텝에 `-var 'ubuntu_version=...'` 직접 추가.

## 변경 파일
| 파일 | 변경 |
|------|------|
| `.github/workflows/build-amd64.yml` | input 블록(L11), `UBUNTU_VERSION` env(L39), packer validate/build에 `-var`(L115,123), 박스/artifact/Vagrant Cloud 이름 8곳 변수화 |
| `.github/workflows/build-arm64.yml` | 동일 구조 대칭 적용, packer 호출 4곳 `-var`, 이름 14곳 변수화 |
| `.github/workflows/validate.yml` | 변경 없음 — 버전 비의존(소스명만 사용) |

## 26.04 CI 빌드 트리거
Actions → "Build AMD64/ARM64 Vagrant Boxes" → **Run workflow** → "Ubuntu version" 드롭다운에서 **26.04** 선택.
(push/PR은 계속 24.04)

## 검증
| 체크 | 결과 |
|------|------|
| YAML 파싱 (양쪽) | PASS |
| 두 워크플로우 대칭 (실수패턴 #10) | 확인 |
| 잔여 `ubuntu-24.04` | 0건 |
| fallback `|| '24.04'` 양쪽 존재 | 확인 (amd64 L39, arm64 L48) |
| upload↔download artifact 이름 일치 | 확인 |

## 비고
- `actionlint` 미설치 → YAML 파서로 대체 검증. 실제 실행 검증은 Phase 5 또는 워크플로우 dispatch 시.
