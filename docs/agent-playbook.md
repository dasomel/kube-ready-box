# Agent Playbook (모델/도구 라우팅)

> `AGENTS.md`에서 분리됨 (OpenForge Agent Engineering 표준, dasomel/openforge#12).
> 모델 티어 선택·병렬화·컨텍스트 관리 일반 원칙은 각 에이전트의 전역 지침을 따릅니다.
> 이 문서는 이 저장소에 특화된 작업 레인만 둡니다.

## 레인별 담당

| 레인 | 티어 | 범위 |
|------|------|------|
| 설계/리뷰 | 상위(Opus급) | 복수 템플릿 리팩토링 계획, 빌드 실패 원인 판단, Mistake Pattern 추가 여부, 되돌릴 수 없는 변경(버전 릴리스, 업로드) 전 검토 |
| 구현 | 중간(Sonnet급) | `*.pkr.hcl`, `packer/scripts/`, GitHub Actions 워크플로우, 문서(AGENTS.md, CHANGELOG.md) |
| 검증/탐색 | 하위(Haiku급) | `shellcheck`, `packer validate` / `packer fmt -check`, 파일 검색, `git status` / `git diff --stat` |

## 작업별 흐름

| 작업 | 흐름 |
|------|------|
| 새 기능 / 스크립트 리팩토링 | 설계 → 구현(같은 OS family의 모든 템플릿 수정) → 검증(shellcheck, validate) |
| 빌드 디버깅 | 로그 분석·원인 판단 → 수정 |
| PR 리뷰 | 로직 리뷰 + lint/validate 병렬 |
| 릴리스 | 변경사항 검토 → 버전 태깅 |

에스컬레이션: 검증 실패 → 구현 레인이 수정, 설계 판단 필요 → 설계 레인, 빌드 실패 원인 불명확 → 설계 레인이 직접 분석.

## 프로젝트 특화 팁

- 같은 OS family 템플릿은 구조가 유사 → 하나만 읽고 diff로 나머지 확인 (family 규칙은 `AGENTS.md`의 Template-family rule).
- `packer/scripts/`는 번호순 → 필요한 스크립트만 선택적으로 로드.
- `.agent/AGENT.md` (800줄+)는 전체 로드 대신 섹션별 참조.
- 스크립트별 shellcheck는 독립 작업이므로 병렬 배치 가능.
