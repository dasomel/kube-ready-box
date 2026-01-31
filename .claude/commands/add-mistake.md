# /add-mistake - 실수 패턴 수동 추가

반복되는 실수 패턴을 기록하여 향후 방지합니다.

## 사용법

이 명령어를 실행하면 실수 패턴을 `.claude/cache/mistake-candidates.jsonl`에 기록합니다.

## 기록 형식

```json
{
  "timestamp": "2024-01-01T00:00:00Z",
  "type": "manual",
  "pattern": "실수 패턴 설명",
  "file": "관련 파일 경로",
  "solution": "해결 방법"
}
```

## 일반적인 실수 패턴 예시

1. **스크립트 추가 후 pkr.hcl 업데이트 누락**
   - 새 스크립트 생성 후 모든 템플릿에 추가 필요

2. **ARM64 빌드 시 VirtualBox 호환성**
   - Apple Silicon에서 VirtualBox ARM64 boot_command 이슈

3. **업로드 전 버전 번호 확인 누락**
   - upload-boxes.sh 실행 전 버전 확인 필요

## 기록 조회

```bash
cat .claude/cache/mistake-candidates.jsonl | jq .
```
