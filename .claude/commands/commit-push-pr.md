# /commit-push-pr - Git 워크플로우

변경사항을 커밋하고 PR을 생성합니다.

## 사전 상태 확인

```bash
echo "=== Git Status ===" && \
git status --short && \
echo "" && echo "=== Recent Commits ===" && \
git log --oneline -5 && \
echo "" && echo "=== Current Branch ===" && \
git branch --show-current
```

## 워크플로우

### 1. 변경사항 확인
관련 파일만 선택적으로 스테이징합니다.

### 2. 커밋 메시지 형식
```
<type>: <subject>

<body>

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Type 종류:**
- `feat`: 새 기능
- `fix`: 버그 수정
- `docs`: 문서 수정
- `chore`: 빌드, 설정 변경
- `refactor`: 리팩토링

### 3. PR 생성
```bash
gh pr create --title "<title>" --body "## Summary
- 변경사항 요약

## Test Plan
- [ ] `./build.sh validate` 통과
- [ ] 로컬 빌드 테스트

Generated with Claude Code"
```

## 체크리스트

- [ ] CHANGELOG.md 업데이트
- [ ] 버전 번호 확인 (필요시)
- [ ] CI 테스트 통과 확인
