---
name: "source-command-add-mistake"
description: "Migrated source command `add-mistake`"
metadata:
  openforge-scope: project
  openforge-owner: dasomel/kube-ready-box
  openforge-maturity: draft
  openforge-version: "1"
---

# source-command-add-mistake

Use this skill when the user asks to run the migrated source command `add-mistake`.

## Command Template

# /add-mistake - 실수 패턴 추가

반복되는 실수 패턴을 `docs/mistakes-log.md`에 기록합니다. 이 문서가 단일 출처이며 `AGENTS.md`나 다른 문서에 복제하지 않습니다.

## 기록 방법

해당 분류 절의 마지막 번호 다음에, 기존 항목과 같은 형식으로 추가합니다.

```markdown
N. **한 줄 제목**
   - 증상: 관측한 현상(명령, 로그 한 줄)
   - 원인: 확인한 원인. 확인하지 못했으면 "미확정"이라고 적습니다
   - 해결: 적용한 조치와 재발 방지 방법
```
