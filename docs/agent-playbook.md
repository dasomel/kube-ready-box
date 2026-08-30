# Agent Playbook (모델/도구 라우팅)

> `AGENTS.md`에서 분리됨 (OpenForge Agent Engineering 표준, dasomel/openforge#12).
> Claude Code 세션은 이 파일 대신 전역 지침(`~/.claude/CLAUDE.md`)의 `routing_doctrine`/`team`을
> 따릅니다 — 이 문서는 Codex 등 그 지침이 미치지 않는 도구/에이전트를 위한 라우팅 제안입니다.

## Agent Team Composition (에이전트 팀 구성)

모델 티어별 역할을 분리하여 비용 효율적이고 품질 높은 작업을 수행합니다.

### 역할 정의

| 역할 | 모델 | 핵심 책임 | 사용 시점 |
|------|------|-----------|-----------|
| **Architect** | Opus | 설계, 리뷰, 의사결정 | 아키텍처 변경, PR 리뷰, 복잡한 디버깅 |
| **Implementer** | Sonnet | 코드 작성, 기능 구현 | 스크립트 수정, pkr.hcl 편집, 문서 업데이트 |
| **Validator** | Haiku | 검증, 린팅, 탐색 | shellcheck, packer validate, 파일 검색 |

### 역할별 가이드라인

**Opus (Architect)**
- 복수 파일에 걸친 리팩토링 계획 수립
- 빌드 실패 원인 분석 및 해결 방향 결정
- Mistake Pattern 추가 여부 판단
- 되돌릴 수 없는 변경(버전 릴리스, 업로드) 전 검토

**Sonnet (Implementer)**
- pkr.hcl 템플릿 수정 (4개 동시 업데이트 주의)
- 프로비저닝 스크립트(packer/scripts/) 작성/수정
- GitHub Actions 워크플로우 편집
- AGENTS.md, CHANGELOG.md 등 문서 작성

**Haiku (Validator)**
- `shellcheck packer/scripts/*.sh` 실행
- `packer validate` / `packer fmt -check` 검증
- Glob/Grep으로 파일 패턴 검색
- 단순 git 상태 확인 (git status, git diff --stat)

### 병렬 실행 패턴

독립적인 작업은 여러 에이전트를 동시에 실행하여 처리 시간 단축:

```
# 예시: 스크립트 동시 shellcheck (각각 Haiku)
Agent 1: shellcheck packer/scripts/01-base.sh
Agent 2: shellcheck packer/scripts/02-os-tuning.sh
Agent 3: shellcheck packer/scripts/03-os-packages.sh
Agent 4: shellcheck packer/scripts/04-k8s-prereq.sh
```

### 작업별 팀 패턴

| 작업 | 구성 | 흐름 |
|------|------|------|
| **새 기능 추가** | Opus → Sonnet → Haiku | 설계 → 구현 → 검증 |
| **빌드 디버깅** | Opus + Haiku | 로그 분석 → 원인 판단 → 수정 |
| **PR 리뷰** | Opus + Haiku(병렬) | Opus: 로직 리뷰, Haiku: lint/validate |
| **스크립트 리팩토링** | Opus → Sonnet → Haiku | 계획 → 4개 템플릿 수정 → shellcheck |
| **빠른 수정** | Sonnet → Haiku | 코드 수정 → 검증 |
| **릴리스** | Opus → Sonnet | 변경사항 검토 → 버전 태깅 |

### 에스컬레이션 규칙

- Haiku가 검증 실패 발견 → Sonnet에게 수정 위임
- Sonnet이 설계 판단 필요 → Opus에게 에스컬레이션
- 빌드 실패 원인 불명확 → Opus가 직접 분석

## Token Strategy (토큰 전략)

모델 선택과 컨텍스트 관리를 최적화하여 비용 대비 최대 효과를 달성합니다.

### 모델 선택 기준

| 복잡도 | 모델 | 예시 작업 | 비용 |
|--------|------|-----------|------|
| **높음** | Opus | 아키텍처 결정, 멀티파일 리팩토링, 복잡한 디버깅 | $$$ |
| **중간** | Sonnet | 코드 편집, 기능 구현, 문서 작성 | $$ |
| **낮음** | Haiku | shellcheck, lint, 파일 검색, 단순 검증 | $ |

### 판단 플로우

```
작업 수신
  ├─ 읽기 전용? (검색, 검증, lint) → Haiku
  ├─ 되돌릴 수 없는 결정? (릴리스, 아키텍처) → Opus
  ├─ 복수 파일 연쇄 수정? → 계획: Opus, 실행: Sonnet
  └─ 단일 파일 수정 → Sonnet
```

### 컨텍스트 윈도우 최적화

| 전략 | 방법 | 효과 |
|------|------|------|
| **서브에이전트 탐색** | 넓은 범위 검색은 서브에이전트에 위임 | 메인 컨텍스트 오염 방지 |
| **타겟 검색 우선** | 파일 경로를 아는 경우 Glob/Grep 직접 사용 | 불필요한 결과 제거 |
| **결과 요약 전달** | 서브에이전트 결과를 요약하여 전달 | 컨텍스트 소비 최소화 |
| **청크 분리** | 대용량 파일은 offset/limit으로 부분 로드 | 전체 파일 로딩 방지 |

**프로젝트 특화 팁:**
- pkr.hcl 4개 템플릿은 구조 유사 → 하나만 읽고 diff로 나머지 확인
- `packer/scripts/` 스크립트는 번호순 → 필요한 스크립트만 선택적 로드
- `.agent/AGENT.md` (700줄+)는 전체 로드 대신 섹션별 참조

### 비용 효율 패턴

**DO (권장)**
- Haiku 병렬 배치: 8개 스크립트 동시 shellcheck
- 읽기 전용 탐색은 항상 Haiku
- Opus는 최종 판단에만: Sonnet 구현 → Haiku 검증 → Opus 리뷰

**DON'T (비권장)**
- Opus로 단순 grep 실행 (→ Haiku 사용)
- Opus로 반복적 단일 파일 수정 (→ Sonnet 사용)
- 메인 컨텍스트에서 대규모 전체 파일 탐색 (→ 서브에이전트 위임)

### 핵심 규칙

1. **Haiku-First**: 의심스러우면 먼저 Haiku로 정보 수집
2. **Opus-Last**: Opus는 최종 판단과 리뷰에만 투입
3. **병렬화**: 독립 작업은 항상 동시 실행 (특히 Haiku 검증)
4. **컨텍스트 격리**: 탐색 결과는 서브에이전트 내에서 소화, 요약만 전달
5. **4-템플릿 규칙**: pkr.hcl 수정 시 반드시 4개 파일 일괄 처리
