# Ralph - 자율 개발 루프 실행

> "Ralph is a Bash loop" - Geoffrey Huntley
> https://ghuntley.com/ralph/

PROMPT.md 파일을 기반으로 Claude를 무한 루프에서 실행하여 자율적으로 작업을 수행합니다.

## 개념

```bash
while :; do cat PROMPT.md | claude --dangerously-skip-permissions; done
```

## 사용법

### 1. PROMPT.md 생성

템플릿 복사:
```bash
cp .claude/templates/PROMPT.md ./PROMPT.md
```

### 2. PROMPT.md 수정

목표, 작업 목록, 완료 조건을 명확히 정의

### 3. Ralph 실행

```bash
# 기본 실행 (무제한 반복)
.claude/scripts/ralph.sh

# 최대 10회 반복
.claude/scripts/ralph.sh --max-iterations 10

# 안전 모드 (권한 확인 포함)
.claude/scripts/ralph.sh --safe

# 사용자 정의 프롬프트 파일
.claude/scripts/ralph.sh ./my-task.md

# 드라이런 (실행 없이 프롬프트만 확인)
.claude/scripts/ralph.sh --dry-run
```

## 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--max-iterations N` | 최대 반복 횟수 | 무제한 |
| `--delay N` | 반복 간 대기 시간(초) | 5 |
| `--safe` | 권한 스킵 없이 실행 | false |
| `--dry-run` | 프롬프트만 출력 | false |

## 로그

실행 로그는 자동 저장:
```
.claude/cache/ralph-logs/ralph-YYYYMMDD-HHMMSS.log
```

## 주의사항

1. **명확한 범위 정의**: PROMPT.md에 작업 범위를 명확히 제한
2. **완료 조건 필수**: 무한 루프 방지를 위해 종료 조건 정의
3. **정기적 확인**: `git diff`로 변경사항 모니터링
4. **백업**: 중요 작업 전 git commit

## 예시 PROMPT.md

```markdown
## 목표
모든 쉘 스크립트에 에러 핸들링 추가

## 작업 목록
1. [ ] packer/scripts/*.sh 검토
2. [ ] set -euo pipefail 누락 파일 수정
3. [ ] shellcheck 경고 해결

## 완료 조건
- shellcheck packer/scripts/*.sh 통과

## 종료
모든 조건 만족 시 "=== RALPH TASK COMPLETE ===" 출력
```

## 실행 중단

`Ctrl+C`로 언제든 중단 가능
