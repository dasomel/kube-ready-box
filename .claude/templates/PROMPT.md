# Ralph Task Prompt Template

> 이 파일을 프로젝트 루트에 PROMPT.md로 복사하고 수정하세요.

## 목표

[1-2줄로 명확하게 목표 정의]

## 컨텍스트

- 프로젝트: Kube Ready Box (Kubernetes-ready Vagrant Box)
- 관련 문서: CLAUDE.md, usage.md
- 현재 상태: [현재 상황 설명]

## 작업 목록

1. [ ] 첫 번째 작업
2. [ ] 두 번째 작업
3. [ ] 세 번째 작업

## 제약 조건

- packer/scripts/*.sh 파일은 `set -euo pipefail` 필수
- Packer 템플릿은 4개 모두 동기화 (virtualbox-amd64, virtualbox-arm64, vmware-amd64, vmware-arm64)
- 새 스크립트 추가 시 모든 pkr.hcl에 provisioner 추가
- packer/ 폴더 외부 파일 수정 주의

## 완료 조건

다음 조건을 모두 만족하면 작업 완료:

1. [ ] 모든 작업 목록 체크
2. [ ] 문법 검증 통과 (shellcheck, packer validate)
3. [ ] 4개 템플릿 일관성 확인

## 검증 명령어

작업 완료 후 다음 명령어로 검증:

```bash
# 쉘 스크립트 검증
shellcheck packer/scripts/*.sh

# Packer 템플릿 검증
cd packer && packer validate .

# Packer 포맷 확인
cd packer && packer fmt -check .
```

## 반복 지시사항

각 반복에서:
1. 작업 목록에서 미완료 항목 확인
2. 한 번에 하나씩 작업 수행
3. 검증 명령어 실행
4. 실패 시 수정 후 재검증
5. 모든 조건 만족 시 종료 메시지 출력

## 종료 조건

모든 완료 조건이 만족되면:
```
=== RALPH TASK COMPLETE ===
All tasks finished successfully.
```
메시지를 출력하세요.

---

# 예시: 디스크 튜닝 스크립트 개선

## 목표

디스크 I/O 최적화 스크립트 개선 및 검증 추가

## 컨텍스트

- 05-disk-tuning.sh 파일 수정
- 07-check-tuning.sh에 검증 로직 추가

## 작업 목록

1. [ ] 05-disk-tuning.sh에 I/O 스케줄러 설정 추가
2. [ ] 07-check-tuning.sh에 디스크 설정 검증 추가
3. [ ] shellcheck 경고 해결

## 제약 조건

- Ubuntu 24.04 호환성 유지
- VirtualBox/VMware 둘 다 동작해야 함
- 기존 설정 덮어쓰기 방지

## 완료 조건

1. [ ] shellcheck packer/scripts/05-disk-tuning.sh 통과
2. [ ] shellcheck packer/scripts/07-check-tuning.sh 통과
3. [ ] packer validate 통과

## 검증 명령어

```bash
shellcheck packer/scripts/05-disk-tuning.sh
shellcheck packer/scripts/07-check-tuning.sh
cd packer && packer validate .
```
